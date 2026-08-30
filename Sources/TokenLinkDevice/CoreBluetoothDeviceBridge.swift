@preconcurrency import CoreBluetooth
import Foundation

public enum BluetoothTransportError: Error, Equatable, Sendable {
  case unavailable
  case operationInProgress
  case timeout
  case peripheralNotFound
  case serviceNotFound
  case characteristicNotFound
  case commandNotificationsUnavailable
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
    case waitingForPower(UInt64)
    case connecting(UInt64)
    case discoveringServices(UInt64)
    case discoveringCharacteristics(UInt64)
    case subscribingCommands(UInt64)
    case ready(UInt64)
  }

  public static var quotaServiceUUID: CBUUID {
    CBUUID(string: "7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C01")
  }

  public static var quotaWriteUUID: CBUUID {
    CBUUID(string: "7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C02")
  }

  /// Read-only capabilities characteristic (protocol v2 firmware).
  public static var capabilitiesUUID: CBUUID {
    CBUUID(string: "7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C03")
  }

  /// Watch → Mac command channel (notify/indicate, protocol v2 firmware).
  public static var commandUUID: CBUUID {
    CBUUID(string: "7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C04")
  }

  private static var hidServiceUUID: CBUUID {
    CBUUID(string: "1812")
  }

  private let queue = DispatchQueue(label: "app.tokenlink.bluetooth")
  private let connectTimeoutSeconds: TimeInterval
  private let writeTimeoutSeconds: TimeInterval
  private let eventStream: AsyncStream<BLETransportEvent>
  private let eventContinuation: AsyncStream<BLETransportEvent>.Continuation
  private var central: CBCentralManager?
  private var discovered: [UUID: CBPeripheral] = [:]
  private var connectedPeripheral: CBPeripheral?
  private var quotaCharacteristic: CBCharacteristic?
  private var capabilitiesCharacteristic: CBCharacteristic?
  private var commandCharacteristic: CBCharacteristic?
  private var scanContinuation: CheckedContinuation<[UUID], Error>?
  private var connectContinuation: CheckedContinuation<Void, Error>?
  private var writeContinuation: CheckedContinuation<Void, Error>?
  private var readContinuation: CheckedContinuation<Data, Error>?
  private var pendingIdentifier: UUID?
  private var connectOperationID: UUID?
  private var writeOperationID: UUID?
  private var readOperationID: UUID?
  private var connectionGeneration: UInt64 = 0
  private var connectionStage: ConnectionStage?
  private var writeConnectionGeneration: UInt64?
  private var readConnectionGeneration: UInt64?
  private let commandStream: AsyncStream<Data>
  private let commandContinuation: AsyncStream<Data>.Continuation
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
    (commandStream, commandContinuation) = AsyncStream.makeStream(
      bufferingPolicy: .bufferingNewest(8))
    super.init()
  }

  deinit {
    eventContinuation.finish()
    commandContinuation.finish()
  }

  public func connectionEvents() -> AsyncStream<BLETransportEvent> {
    eventStream
  }

  public func commandEvents() -> AsyncStream<Data> {
    commandStream
  }

  public func diagnosticSnapshot() async -> BluetoothDiagnosticSnapshot {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        let authorization: BluetoothAuthorizationState =
          switch CBManager.authorization {
          case .notDetermined: .notDetermined
          case .restricted: .restricted
          case .denied: .denied
          case .allowedAlways: .allowed
          @unknown default: .unavailable
          }
        let centralState: BluetoothCentralState =
          switch central?.state {
          case nil: .notInitialized
          case .unknown: .unknown
          case .resetting: .resetting
          case .unsupported: .unsupported
          case .unauthorized: .unauthorized
          case .poweredOff: .poweredOff
          case .poweredOn: .poweredOn
          @unknown default: .unknown
          }
        let connectionStep: BluetoothConnectionStep =
          switch connectionStage {
          case nil: scanContinuation == nil ? .idle : .scanning
          case .waitingForPower: .waitingForPower
          case .connecting: .connecting
          case .discoveringServices: .discoveringServices
          case .discoveringCharacteristics: .discoveringCharacteristics
          case .subscribingCommands: .subscribingCommands
          case .ready: .ready
          }
        continuation.resume(
          returning: BluetoothDiagnosticSnapshot(
            authorization: authorization,
            centralState: centralState,
            connectionStep: connectionStep,
            connectedIdentifier: connectedPeripheral?.identifier,
            quotaCharacteristicAvailable: quotaCharacteristic != nil,
            capabilitiesCharacteristicAvailable: capabilitiesCharacteristic != nil,
            commandCharacteristicAvailable: commandCharacteristic != nil,
            commandNotificationsActive: commandCharacteristic?.isNotifying == true))
      }
    }
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
          connectionGeneration &+= 1
          let generation = connectionGeneration
          pendingIdentifier = identifier
          connectOperationID = operationID
          connectContinuation = continuation
          connectionStage = .waitingForPower(generation)
          if central.state == .poweredOn {
            beginConnect(identifier: identifier, generation: generation)
          } else if central.state != .unknown && central.state != .resetting {
            resumeConnect(throwing: BluetoothTransportError.unavailable)
          }
          queue.asyncAfter(deadline: .now() + connectTimeoutSeconds) { [weak self] in
            self?.timeoutConnect(operationID: operationID)
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

  /// Reads the v2 capabilities characteristic; nil when the firmware does not
  /// expose it. Follows the same "resume each continuation exactly once"
  /// discipline as writes.
  public func readCapabilities() async throws -> WatchCapabilities? {
    let data: Data = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Data, Error>) in
        queue.async { [self] in
          guard readContinuation == nil else {
            continuation.resume(throwing: BluetoothTransportError.operationInProgress)
            return
          }
          guard let peripheral = connectedPeripheral,
            peripheral.state == .connected,
            case .ready(let generation) = connectionStage
          else {
            continuation.resume(throwing: BluetoothTransportError.disconnected)
            return
          }
          guard let capabilitiesCharacteristic else {
            continuation.resume(returning: Data())
            return
          }
          let operationID = UUID()
          readOperationID = operationID
          readConnectionGeneration = generation
          readContinuation = continuation
          peripheral.readValue(for: capabilitiesCharacteristic)
          queue.asyncAfter(deadline: .now() + writeTimeoutSeconds) { [weak self] in
            self?.timeoutRead(operationID: operationID)
          }
        }
      }
    } onCancel: { [weak self] in
      self?.queue.async { [weak self] in
        self?.cancelRead()
      }
    }
    guard !data.isEmpty else { return nil }
    return try JSONDecoder().decode(WatchCapabilities.self, from: data)
  }

  public func disconnect() async {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        disconnectContinuations.append(continuation)
        if disconnectingPeripheral != nil { return }

        let peripheral = connectedPeripheral ?? pendingPeripheral()
        resumeConnect(throwing: BluetoothTransportError.disconnected)
        resumeWrite(throwing: BluetoothTransportError.disconnected)
        resumeRead(throwing: BluetoothTransportError.disconnected)
        connectionStage = nil
        quotaCharacteristic = nil
        capabilitiesCharacteristic = nil
        commandCharacteristic = nil
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

  /// CBCentralManager always begins life in `.unknown`, and on first launch
  /// macOS may also be resolving the Bluetooth TCC prompt. Wait for the
  /// delegate's powered-on transition before retrieving the pinned device.
  private func beginConnect(identifier: UUID, generation: UInt64) {
    guard let central, pendingIdentifier == identifier,
      case .waitingForPower(generation) = connectionStage
    else { return }
    let retrieved = central.retrievePeripherals(withIdentifiers: [identifier]).first
    guard let peripheral = discovered[identifier] ?? retrieved else {
      resumeConnect(throwing: BluetoothTransportError.peripheralNotFound)
      return
    }
    // CoreBluetooth does not retain a peripheral passed to `connect`. A bound
    // device is commonly returned only by `retrievePeripherals`, so keep the
    // object alive until the delegate either connects or fails.
    discovered[identifier] = peripheral
    let peripheralIdentity = ObjectIdentifier(peripheral)
    let isQuarantined =
      ignoredLateDisconnects[peripheralIdentity].map { $0 > Date() } ?? false
    if !isQuarantined {
      ignoredLateDisconnects.removeValue(forKey: peripheralIdentity)
    }
    guard peripheral.state != .disconnecting, !isQuarantined else {
      resumeConnect(throwing: BluetoothTransportError.disconnected)
      return
    }
    connectionStage = .connecting(generation)
    peripheral.delegate = self
    if peripheral.state == .connected {
      connectedPeripheral = peripheral
      connectionStage = .discoveringServices(generation)
      peripheral.discoverServices([Self.quotaServiceUUID])
    } else {
      central.connect(peripheral)
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

  private func finishConnect(peripheral: CBPeripheral, generation: UInt64) {
    connectionStage = .ready(generation)
    resumeConnect()
    eventContinuation.yield(.connected(peripheral.identifier))
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

  private func resumeRead(
    throwing error: Error? = nil,
    returning data: Data? = nil
  ) {
    guard let continuation = readContinuation else { return }
    readContinuation = nil
    readOperationID = nil
    readConnectionGeneration = nil
    if let error {
      continuation.resume(throwing: error)
    } else {
      continuation.resume(returning: data ?? Data())
    }
  }

  private func timeoutRead(operationID: UUID) {
    guard readOperationID == operationID else { return }
    resumeRead(throwing: BluetoothTransportError.timeout)
  }

  private func cancelRead() {
    guard readContinuation != nil else { return }
    resumeRead(throwing: CancellationError())
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
    capabilitiesCharacteristic = nil
    commandCharacteristic = nil
    connectionStage = nil
    writeConnectionGeneration = nil
    readConnectionGeneration = nil
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
    capabilitiesCharacteristic = nil
    commandCharacteristic = nil
    connectionStage = nil
    writeConnectionGeneration = nil
    readConnectionGeneration = nil
    if let identifier {
      eventContinuation.yield(.disconnected(identifier))
    }
    let continuations = disconnectContinuations
    disconnectContinuations.removeAll()
    for continuation in continuations { continuation.resume() }
  }

  private func timeoutConnect(operationID: UUID) {
    guard connectOperationID == operationID else { return }
    if let peripheral = pendingPeripheral(), let central {
      beginDisconnect(peripheral: peripheral, central: central)
    }
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
    if case .waitingForPower(let generation) = connectionStage,
      let identifier = pendingIdentifier
    {
      if central.state == .poweredOn {
        beginConnect(identifier: identifier, generation: generation)
      } else if central.state != .unknown && central.state != .resetting {
        resumeConnect(throwing: BluetoothTransportError.unavailable)
      }
    }
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
    capabilitiesCharacteristic = nil
    commandCharacteristic = nil
    let failure = BluetoothTransportError.system(
      error?.localizedDescription ?? "Peripheral disconnected.")
    resumeConnect(throwing: failure)
    resumeWrite(throwing: failure)
    resumeRead(throwing: failure)
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
    peripheral.discoverCharacteristics(
      [Self.quotaWriteUUID, Self.capabilitiesUUID, Self.commandUUID],
      for: service)
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
    // The v2 characteristics are optional: v1 firmware only carries the quota
    // write characteristic, and the bridge silently stays on protocol v1.
    capabilitiesCharacteristic = service.characteristics?.first(where: {
      $0.uuid == Self.capabilitiesUUID
    })
    if let command = service.characteristics?.first(where: {
      $0.uuid == Self.commandUUID
    }) {
      commandCharacteristic = command
      // A successful physical connection is not enough for protocol v2:
      // session focus and refresh travel over C04 notifications. Do not expose
      // the bridge as connected until CoreBluetooth confirms the CCCD write.
      connectionStage = .subscribingCommands(generation)
      peripheral.setNotifyValue(true, for: command)
      return
    }
    finishConnect(peripheral: peripheral, generation: generation)
  }

  public func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard peripheral === connectedPeripheral,
      characteristic === commandCharacteristic,
      characteristic.uuid == Self.commandUUID,
      case .subscribingCommands(let generation) = connectionStage
    else { return }
    if error != nil {
      resumeConnect(throwing: BluetoothTransportError.commandNotificationsUnavailable)
      return
    }
    guard characteristic.isNotifying else {
      resumeConnect(throwing: BluetoothTransportError.commandNotificationsUnavailable)
      return
    }
    finishConnect(peripheral: peripheral, generation: generation)
  }

  public func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard peripheral === connectedPeripheral else { return }
    // Watch → Mac command frames arrive as notifications on …C04.
    if characteristic.uuid == Self.commandUUID,
      characteristic === commandCharacteristic
    {
      if let value = characteristic.value, !value.isEmpty {
        commandContinuation.yield(value)
      }
      return
    }
    guard characteristic.uuid == Self.capabilitiesUUID,
      characteristic === capabilitiesCharacteristic,
      case .ready(let generation) = connectionStage,
      readConnectionGeneration == generation
    else { return }
    if let error {
      resumeRead(throwing: BluetoothTransportError.system(error.localizedDescription))
    } else if let value = characteristic.value {
      resumeRead(returning: value)
    } else {
      resumeRead(throwing: BluetoothTransportError.characteristicNotFound)
    }
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
