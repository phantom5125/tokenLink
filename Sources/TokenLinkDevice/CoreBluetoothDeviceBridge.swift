@preconcurrency import CoreBluetooth
import Foundation

public enum BluetoothTransportError: Error, Equatable, Sendable {
  case unavailable
  case operationInProgress
  case timeout
  case peripheralNotFound
  case serviceNotFound
  case characteristicNotFound
  case disconnected
  case system(String)
}

public enum StopWatchDiscoveryFilter {
  public static func isCandidate(name: String?, serviceUUIDs: [String]) -> Bool {
    if name == "Codex Micro" { return true }
    return serviceUUIDs.contains {
      $0.caseInsensitiveCompare("7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C01") == .orderedSame
    }
  }
}

public final class CoreBluetoothTransport: NSObject, BLETransport, @unchecked Sendable {
  private enum ConnectionStage: Equatable {
    case connecting(UInt64)
    case discoveringServices(UInt64)
    case discoveringCharacteristics(UInt64)
    case ready(UInt64)
  }

  public static var quotaServiceUUID: CBUUID {
    CBUUID(string: "7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C01")
  }

  public static var quotaWriteUUID: CBUUID {
    CBUUID(string: "7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C02")
  }

  private static var hidServiceUUID: CBUUID {
    CBUUID(string: "1812")
  }

  private let queue = DispatchQueue(label: "io.github.phantom5125.tokenlink.bluetooth")
  private let connectTimeoutSeconds: TimeInterval
  private let writeTimeoutSeconds: TimeInterval
  private let eventStream: AsyncStream<BLETransportEvent>
  private let eventContinuation: AsyncStream<BLETransportEvent>.Continuation
  private var central: CBCentralManager?
  private var discovered: [UUID: CBPeripheral] = [:]
  private var connectedPeripheral: CBPeripheral?
  private var quotaCharacteristic: CBCharacteristic?
  private var scanContinuation: CheckedContinuation<[UUID], Error>?
  private var connectContinuation: CheckedContinuation<Void, Error>?
  private var writeContinuation: CheckedContinuation<Void, Error>?
  private var pendingIdentifier: UUID?
  private var connectOperationID: UUID?
  private var writeOperationID: UUID?
  private var connectionGeneration: UInt64 = 0
  private var connectionStage: ConnectionStage?
  private var writeConnectionGeneration: UInt64?
  private var disconnectingPeripheral: CBPeripheral?
  private var disconnectOperationID: UUID?
  private var disconnectContinuations: [CheckedContinuation<Void, Never>] = []
  private var ignoredLateDisconnects: [ObjectIdentifier: Date] = [:]

  var hasInitializedCentralManager: Bool {
    queue.sync { central != nil }
  }

  public init(
    connectTimeoutSeconds: TimeInterval = 10,
    writeTimeoutSeconds: TimeInterval = 5
  ) {
    self.connectTimeoutSeconds = connectTimeoutSeconds
    self.writeTimeoutSeconds = writeTimeoutSeconds
    (eventStream, eventContinuation) = AsyncStream.makeStream(
      bufferingPolicy: .bufferingNewest(8))
    super.init()
  }

  deinit {
    eventContinuation.finish()
  }

  public func connectionEvents() -> AsyncStream<BLETransportEvent> {
    eventStream
  }

  public func discoveredIdentifiers() async throws -> [UUID] {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<[UUID], Error>) in
      queue.async { [self] in
        guard scanContinuation == nil else {
          continuation.resume(throwing: BluetoothTransportError.operationInProgress)
          return
        }
        let central = manager()
        discovered.removeAll()
        scanContinuation = continuation
        if central.state == .poweredOn {
          startScan()
        } else if central.state != .unknown && central.state != .resetting {
          finishScan(throwing: BluetoothTransportError.unavailable)
        }
      }
    }
  }

  public func connect(identifier: UUID) async throws {
    let operationID = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        queue.async { [self] in
          guard connectContinuation == nil, disconnectingPeripheral == nil else {
            continuation.resume(throwing: BluetoothTransportError.operationInProgress)
            return
          }
          let central = manager()
          let retrieved = central.retrievePeripherals(withIdentifiers: [identifier]).first
          guard let peripheral = discovered[identifier] ?? retrieved else {
            continuation.resume(throwing: BluetoothTransportError.peripheralNotFound)
            return
          }
          let peripheralIdentity = ObjectIdentifier(peripheral)
          let isQuarantined =
            ignoredLateDisconnects[peripheralIdentity].map { $0 > Date() } ?? false
          if !isQuarantined {
            ignoredLateDisconnects.removeValue(forKey: peripheralIdentity)
          }
          guard peripheral.state != .disconnecting, !isQuarantined else {
            continuation.resume(throwing: BluetoothTransportError.disconnected)
            return
          }
          connectionGeneration &+= 1
          let generation = connectionGeneration
          pendingIdentifier = identifier
          connectOperationID = operationID
          connectContinuation = continuation
          connectionStage = .connecting(generation)
          peripheral.delegate = self
          if peripheral.state == .connected {
            connectedPeripheral = peripheral
            connectionStage = .discoveringServices(generation)
            peripheral.discoverServices([Self.quotaServiceUUID])
          } else {
            central.connect(peripheral)
          }
          queue.asyncAfter(deadline: .now() + connectTimeoutSeconds) { [weak self] in
            self?.timeoutConnect(operationID: operationID, peripheral: peripheral)
          }
        }
      }
    } onCancel: { [weak self] in
      self?.queue.async { [weak self] in
        self?.cancelConnect(operationID: operationID)
      }
    }
  }

  public func writeWithResponse(_ data: Data) async throws {
    let operationID = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        queue.async { [self] in
          guard writeContinuation == nil else {
            continuation.resume(throwing: BluetoothTransportError.operationInProgress)
            return
          }
          guard let peripheral = connectedPeripheral,
            peripheral.state == .connected,
            let quotaCharacteristic,
            case .ready(let generation) = connectionStage
          else {
            continuation.resume(throwing: BluetoothTransportError.disconnected)
            return
          }
          writeOperationID = operationID
          writeConnectionGeneration = generation
          writeContinuation = continuation
          peripheral.writeValue(data, for: quotaCharacteristic, type: .withResponse)
          queue.asyncAfter(deadline: .now() + writeTimeoutSeconds) { [weak self] in
            self?.timeoutWrite(operationID: operationID, peripheral: peripheral)
          }
        }
      }
    } onCancel: { [weak self] in
      self?.queue.async { [weak self] in
        self?.cancelWrite(operationID: operationID)
      }
    }
  }

  public func disconnect() async {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        disconnectContinuations.append(continuation)
        if disconnectingPeripheral != nil { return }

        let peripheral = connectedPeripheral ?? pendingPeripheral()
        resumeConnect(throwing: BluetoothTransportError.disconnected)
        resumeWrite(throwing: BluetoothTransportError.disconnected)
        connectionStage = nil
        quotaCharacteristic = nil
        connectedPeripheral = nil

        guard let peripheral, let central, peripheral.state != .disconnected else {
          finishDisconnect(peripheral: peripheral)
          return
        }
        beginDisconnect(peripheral: peripheral, central: central)
      }
    }
  }

  private func startScan() {
    guard let central else {
      finishScan(throwing: BluetoothTransportError.unavailable)
      return
    }
    let quotaConnected = central.retrieveConnectedPeripherals(
      withServices: [Self.quotaServiceUUID])
    let hidConnected = central.retrieveConnectedPeripherals(
      withServices: [Self.hidServiceUUID])
    for peripheral in quotaConnected {
      discovered[peripheral.identifier] = peripheral
    }
    for peripheral in hidConnected
    where StopWatchDiscoveryFilter.isCandidate(
      name: peripheral.name,
      serviceUUIDs: [])
    {
      discovered[peripheral.identifier] = peripheral
    }

    // Scan broadly because a bonded HID connection can retain an older service
    // cache. Candidates are filtered by advertised name/private UUID, and no
    // connection occurs until the user explicitly selects an identifier.
    central.scanForPeripherals(
      withServices: nil,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      self?.finishScan()
    }
  }

  private func finishScan(throwing error: Error? = nil) {
    central?.stopScan()
    guard let continuation = scanContinuation else { return }
    scanContinuation = nil
    if let error {
      continuation.resume(throwing: error)
    } else {
      continuation.resume(
        returning: discovered.keys.sorted {
          $0.uuidString < $1.uuidString
        })
    }
  }

  private func resumeConnect(throwing error: Error? = nil) {
    guard let continuation = connectContinuation else { return }
    connectContinuation = nil
    connectOperationID = nil
    pendingIdentifier = nil
    if error != nil { connectionStage = nil }
    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
  }

  private func resumeWrite(throwing error: Error? = nil) {
    guard let continuation = writeContinuation else { return }
    writeContinuation = nil
    writeOperationID = nil
    writeConnectionGeneration = nil
    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
  }

  private func pendingPeripheral() -> CBPeripheral? {
    guard let pendingIdentifier else { return nil }
    return discovered[pendingIdentifier]
      ?? central?.retrievePeripherals(withIdentifiers: [pendingIdentifier]).first
  }

  private func beginDisconnect(peripheral: CBPeripheral, central: CBCentralManager) {
    guard disconnectingPeripheral == nil else { return }
    let operationID = UUID()
    disconnectingPeripheral = peripheral
    disconnectOperationID = operationID
    connectedPeripheral = nil
    quotaCharacteristic = nil
    connectionStage = nil
    writeConnectionGeneration = nil
    central.cancelPeripheralConnection(peripheral)
    queue.asyncAfter(deadline: .now() + 2) { [weak self] in
      self?.finishDisconnect(peripheral: peripheral, operationID: operationID)
    }
  }

  private func finishDisconnect(
    peripheral: CBPeripheral?,
    operationID: UUID? = nil
  ) {
    if let operationID, operationID != disconnectOperationID { return }
    if let active = disconnectingPeripheral,
      let peripheral,
      active !== peripheral
    {
      return
    }
    let identifier = (disconnectingPeripheral ?? peripheral)?.identifier
    if operationID != nil, let peripheral, peripheral.state != .disconnected {
      ignoredLateDisconnects[ObjectIdentifier(peripheral)] = Date(timeIntervalSinceNow: 5)
    }
    disconnectingPeripheral = nil
    disconnectOperationID = nil
    connectedPeripheral = nil
    quotaCharacteristic = nil
    connectionStage = nil
    writeConnectionGeneration = nil
    if let identifier {
      eventContinuation.yield(.disconnected(identifier))
    }
    let continuations = disconnectContinuations
    disconnectContinuations.removeAll()
    for continuation in continuations { continuation.resume() }
  }

  private func timeoutConnect(operationID: UUID, peripheral: CBPeripheral) {
    guard connectOperationID == operationID else { return }
    if let central { beginDisconnect(peripheral: peripheral, central: central) }
    resumeConnect(throwing: BluetoothTransportError.timeout)
  }

  private func cancelConnect(operationID: UUID) {
    guard connectOperationID == operationID else { return }
    if let peripheral = pendingPeripheral(), let central {
      beginDisconnect(peripheral: peripheral, central: central)
    }
    resumeConnect(throwing: CancellationError())
  }

  private func timeoutWrite(operationID: UUID, peripheral: CBPeripheral) {
    guard writeOperationID == operationID else { return }
    if let central { beginDisconnect(peripheral: peripheral, central: central) }
    resumeWrite(throwing: BluetoothTransportError.timeout)
  }

  private func cancelWrite(operationID: UUID) {
    guard writeOperationID == operationID else { return }
    if let peripheral = connectedPeripheral, let central {
      beginDisconnect(peripheral: peripheral, central: central)
    }
    resumeWrite(throwing: CancellationError())
  }

  private func manager() -> CBCentralManager {
    if let central { return central }
    let manager = CBCentralManager(delegate: self, queue: queue)
    central = manager
    return manager
  }
}

extension CoreBluetoothTransport: CBCentralManagerDelegate {
  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state == .poweredOn, scanContinuation != nil {
      startScan()
    } else if central.state != .poweredOn,
      central.state != .unknown,
      central.state != .resetting,
      scanContinuation != nil
    {
      finishScan(throwing: BluetoothTransportError.unavailable)
    }
  }

  public func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi: NSNumber
  ) {
    let name =
      peripheral.name
      ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
    let services =
      (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
      .map(\.uuidString) ?? []
    guard
      StopWatchDiscoveryFilter.isCandidate(
        name: name,
        serviceUUIDs: services)
    else { return }
    discovered[peripheral.identifier] = peripheral
  }

  public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard peripheral.identifier == pendingIdentifier,
      case .connecting(let generation) = connectionStage
    else {
      central.cancelPeripheralConnection(peripheral)
      return
    }
    connectedPeripheral = peripheral
    connectionStage = .discoveringServices(generation)
    peripheral.discoverServices([Self.quotaServiceUUID])
  }

  public func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    if ignoredLateDisconnects.removeValue(forKey: ObjectIdentifier(peripheral)) != nil { return }
    guard peripheral.identifier == pendingIdentifier,
      case .connecting = connectionStage
    else { return }
    resumeConnect(
      throwing: BluetoothTransportError.system(
        error?.localizedDescription ?? "Connection failed."))
  }

  public func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    let objectIdentifier = ObjectIdentifier(peripheral)
    if ignoredLateDisconnects.removeValue(forKey: objectIdentifier) != nil { return }
    if let disconnectingPeripheral, disconnectingPeripheral === peripheral {
      finishDisconnect(peripheral: peripheral)
      return
    }
    guard
      peripheral === connectedPeripheral
        || peripheral.identifier == pendingIdentifier
    else { return }
    connectedPeripheral = nil
    quotaCharacteristic = nil
    let failure = BluetoothTransportError.system(
      error?.localizedDescription ?? "Peripheral disconnected.")
    resumeConnect(throwing: failure)
    resumeWrite(throwing: failure)
    eventContinuation.yield(.disconnected(peripheral.identifier))
  }
}

extension CoreBluetoothTransport: CBPeripheralDelegate {
  public func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverServices error: Error?
  ) {
    guard peripheral === connectedPeripheral,
      case .discoveringServices(let generation) = connectionStage
    else { return }
    if let error {
      resumeConnect(throwing: BluetoothTransportError.system(error.localizedDescription))
      return
    }
    guard
      let service = peripheral.services?.first(where: {
        $0.uuid == Self.quotaServiceUUID
      })
    else {
      resumeConnect(throwing: BluetoothTransportError.serviceNotFound)
      return
    }
    connectionStage = .discoveringCharacteristics(generation)
    peripheral.discoverCharacteristics([Self.quotaWriteUUID], for: service)
  }

  public func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard peripheral === connectedPeripheral,
      case .discoveringCharacteristics(let generation) = connectionStage
    else { return }
    if let error {
      resumeConnect(throwing: BluetoothTransportError.system(error.localizedDescription))
      return
    }
    guard service.uuid == Self.quotaServiceUUID,
      let characteristic = service.characteristics?.first(where: {
        $0.uuid == Self.quotaWriteUUID
      })
    else {
      resumeConnect(throwing: BluetoothTransportError.characteristicNotFound)
      return
    }
    quotaCharacteristic = characteristic
    connectionStage = .ready(generation)
    resumeConnect()
    eventContinuation.yield(.connected(peripheral.identifier))
  }

  public func peripheral(
    _ peripheral: CBPeripheral,
    didWriteValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard peripheral === connectedPeripheral,
      characteristic === quotaCharacteristic,
      characteristic.uuid == Self.quotaWriteUUID,
      case .ready(let generation) = connectionStage,
      writeConnectionGeneration == generation
    else { return }
    if let error {
      resumeWrite(throwing: BluetoothTransportError.system(error.localizedDescription))
    } else {
      resumeWrite()
    }
  }
}
