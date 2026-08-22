import CoreBluetooth
import Foundation

public enum CoreBluetoothTransportError: Error, Equatable {
    case bluetoothUnavailable
    case peripheralNotFound
    case serviceNotFound
    case characteristicNotFound
    case connectionFailed
    case writeRejected
}

/// CoreBluetooth transport for the private StopWatch quota GATT service.
/// Tests must use a `BLETransport` fake; this type is the hardware boundary only.
public final class CoreBluetoothTransport: NSObject, BLETransport, @unchecked Sendable {
    public static var quotaServiceUUID: CBUUID { CBUUID(string: "7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C01") }
    public static var quotaWriteUUID: CBUUID { CBUUID(string: "7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C02") }

    private let central: CBCentralManager
    private let lock = NSLock()

    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    // Continuations are stored as optionals and cleared before resuming so each
    // delegate callback resumes its continuation exactly once.
    private var scanContinuation: CheckedContinuation<[UUID], Never>?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var writeContinuation: CheckedContinuation<Void, Error>?

    public override init() {
        central = CBCentralManager(delegate: nil, queue: nil)
        super.init()
        central.delegate = self
    }

    public func discoveredIdentifiers() async throws -> [UUID] {
        guard central.state == .poweredOn else { throw CoreBluetoothTransportError.bluetoothUnavailable }
        return await withCheckedContinuation { continuation in
            lock.withLock { scanContinuation = continuation }
            central.scanForPeripherals(withServices: [Self.quotaServiceUUID])
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.finishScan()
            }
        }
    }

    private func finishScan() {
        let continuation = lock.withLock { () -> CheckedContinuation<[UUID], Never>? in
            defer { scanContinuation = nil }
            return scanContinuation
        }
        central.stopScan()
        if let continuation {
            continuation.resume(returning: lock.withLock { Array(peripherals.keys) })
        }
    }

    public func connect(identifier: UUID) async throws {
        let peripheral = lock.withLock { () -> CBPeripheral? in
            if let known = peripherals[identifier] { return known }
            return central.retrievePeripherals(withIdentifiers: [identifier]).first
        }
        guard let peripheral else { throw CoreBluetoothTransportError.peripheralNotFound }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock {
                connectContinuation = continuation
                connectedPeripheral = peripheral
            }
            peripheral.delegate = self
            central.connect(peripheral)
        }
    }

    public func writeWithResponse(_ data: Data) async throws {
        guard let peripheral = lock.withLock({ connectedPeripheral }) else {
            throw CoreBluetoothTransportError.peripheralNotFound
        }
        let characteristic = try await ensureWriteCharacteristic(on: peripheral)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock { writeContinuation = continuation }
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }

    public func disconnect() async {
        guard let peripheral = lock.withLock({ connectedPeripheral }) else { return }
        central.cancelPeripheralConnection(peripheral)
        lock.withLock {
            connectedPeripheral = nil
            writeCharacteristic = nil
        }
    }

    private func ensureWriteCharacteristic(on peripheral: CBPeripheral) async throws -> CBCharacteristic {
        if let cached = lock.withLock({ writeCharacteristic }) { return cached }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.quotaServiceUUID }) else {
            peripheral.discoverServices([Self.quotaServiceUUID])
            try await Task.sleep(for: .milliseconds(500))
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.quotaServiceUUID }) else {
                throw CoreBluetoothTransportError.serviceNotFound
            }
            return try await discoverWriteCharacteristic(on: peripheral, in: service)
        }
        return try await discoverWriteCharacteristic(on: peripheral, in: service)
    }

    private func discoverWriteCharacteristic(
        on peripheral: CBPeripheral, in service: CBService
    ) async throws -> CBCharacteristic {
        if let characteristic = service.characteristics?.first(where: { $0.uuid == Self.quotaWriteUUID }) {
            lock.withLock { writeCharacteristic = characteristic }
            return characteristic
        }
        peripheral.discoverCharacteristics([Self.quotaWriteUUID], for: service)
        try await Task.sleep(for: .milliseconds(500))
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.quotaWriteUUID }) else {
            throw CoreBluetoothTransportError.characteristicNotFound
        }
        lock.withLock { writeCharacteristic = characteristic }
        return characteristic
    }
}

extension CoreBluetoothTransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {}

    public func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        lock.withLock { peripherals[peripheral.identifier] = peripheral }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { connectContinuation = nil }
            return connectContinuation
        }
        peripheral.discoverServices([Self.quotaServiceUUID])
        continuation?.resume()
    }

    public func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { connectContinuation = nil }
            return connectContinuation
        }
        continuation?.resume(throwing: error ?? CoreBluetoothTransportError.connectionFailed)
    }
}

extension CoreBluetoothTransport: CBPeripheralDelegate {
    public func peripheral(
        _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        guard characteristic.uuid == Self.quotaWriteUUID else { return }
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { writeContinuation = nil }
            return writeContinuation
        }
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}
