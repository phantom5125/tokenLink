@preconcurrency import CoreBluetooth
import Foundation

public enum BluetoothTransportError: Error, Equatable, Sendable {
    case unavailable
    case operationInProgress
    case peripheralNotFound
    case serviceNotFound
    case characteristicNotFound
    case disconnected
    case system(String)
}

public final class CoreBluetoothTransport: NSObject, BLETransport, @unchecked Sendable {
    public static var quotaServiceUUID: CBUUID {
        CBUUID(string: "7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C01")
    }

    public static var quotaWriteUUID: CBUUID {
        CBUUID(string: "7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C02")
    }

    private let queue = DispatchQueue(label: "io.github.phantom5125.tokenlink.bluetooth")
    private var central: CBCentralManager!
    private var discovered: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var quotaCharacteristic: CBCharacteristic?
    private var scanContinuation: CheckedContinuation<[UUID], Error>?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var writeContinuation: CheckedContinuation<Void, Error>?
    private var pendingIdentifier: UUID?

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    public func discoveredIdentifiers() async throws -> [UUID] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UUID], Error>) in
            queue.async { [self] in
                guard scanContinuation == nil else {
                    continuation.resume(throwing: BluetoothTransportError.operationInProgress)
                    return
                }
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard connectContinuation == nil else {
                    continuation.resume(throwing: BluetoothTransportError.operationInProgress)
                    return
                }
                let retrieved = central.retrievePeripherals(withIdentifiers: [identifier]).first
                guard let peripheral = discovered[identifier] ?? retrieved else {
                    continuation.resume(throwing: BluetoothTransportError.peripheralNotFound)
                    return
                }
                pendingIdentifier = identifier
                connectContinuation = continuation
                peripheral.delegate = self
                central.connect(peripheral)
            }
        }
    }

    public func writeWithResponse(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard writeContinuation == nil else {
                    continuation.resume(throwing: BluetoothTransportError.operationInProgress)
                    return
                }
                guard let peripheral = connectedPeripheral,
                      peripheral.state == .connected,
                      let quotaCharacteristic
                else {
                    continuation.resume(throwing: BluetoothTransportError.disconnected)
                    return
                }
                writeContinuation = continuation
                peripheral.writeValue(data, for: quotaCharacteristic, type: .withResponse)
            }
        }
    }

    public func disconnect() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if let connectedPeripheral {
                    central.cancelPeripheralConnection(connectedPeripheral)
                }
                connectedPeripheral = nil
                quotaCharacteristic = nil
                resumeConnect(throwing: BluetoothTransportError.disconnected)
                resumeWrite(throwing: BluetoothTransportError.disconnected)
                continuation.resume()
            }
        }
    }

    private func startScan() {
        central.scanForPeripherals(
            withServices: [Self.quotaServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.finishScan()
        }
    }

    private func finishScan(throwing error: Error? = nil) {
        central.stopScan()
        guard let continuation = scanContinuation else { return }
        scanContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: discovered.keys.sorted {
                $0.uuidString < $1.uuidString
            })
        }
    }

    private func resumeConnect(throwing error: Error? = nil) {
        guard let continuation = connectContinuation else { return }
        connectContinuation = nil
        pendingIdentifier = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }

    private func resumeWrite(throwing error: Error? = nil) {
        guard let continuation = writeContinuation else { return }
        writeContinuation = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }
}

extension CoreBluetoothTransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, scanContinuation != nil {
            startScan()
        } else if central.state != .poweredOn,
                  central.state != .unknown,
                  central.state != .resetting,
                  scanContinuation != nil {
            finishScan(throwing: BluetoothTransportError.unavailable)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discovered[peripheral.identifier] = peripheral
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == pendingIdentifier else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        connectedPeripheral = peripheral
        peripheral.discoverServices([Self.quotaServiceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peripheral.identifier == pendingIdentifier else { return }
        resumeConnect(throwing: BluetoothTransportError.system(
            error?.localizedDescription ?? "Connection failed."))
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard peripheral.identifier == connectedPeripheral?.identifier
                || peripheral.identifier == pendingIdentifier else { return }
        connectedPeripheral = nil
        quotaCharacteristic = nil
        let failure = BluetoothTransportError.system(
            error?.localizedDescription ?? "Peripheral disconnected.")
        resumeConnect(throwing: failure)
        resumeWrite(throwing: failure)
    }
}

extension CoreBluetoothTransport: CBPeripheralDelegate {
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let error {
            resumeConnect(throwing: BluetoothTransportError.system(error.localizedDescription))
            return
        }
        guard let service = peripheral.services?.first(where: {
            $0.uuid == Self.quotaServiceUUID
        }) else {
            resumeConnect(throwing: BluetoothTransportError.serviceNotFound)
            return
        }
        peripheral.discoverCharacteristics([Self.quotaWriteUUID], for: service)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            resumeConnect(throwing: BluetoothTransportError.system(error.localizedDescription))
            return
        }
        guard service.uuid == Self.quotaServiceUUID,
              let characteristic = service.characteristics?.first(where: {
                  $0.uuid == Self.quotaWriteUUID
              }) else {
            resumeConnect(throwing: BluetoothTransportError.characteristicNotFound)
            return
        }
        quotaCharacteristic = characteristic
        resumeConnect()
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.quotaWriteUUID else { return }
        if let error {
            resumeWrite(throwing: BluetoothTransportError.system(error.localizedDescription))
        } else {
            resumeWrite()
        }
    }
}
