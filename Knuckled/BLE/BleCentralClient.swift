import Foundation
import CoreBluetooth
import KnuckledCore

/// Client side: scans for the service, connects, subscribes, runs the PIN
/// handshake (reliable writes), returns a live GameLink. Blocking facade —
/// call off the CB queue (ConnectionSession backgrounds it).
final class BleCentralClient: NSObject {
    private var manager: CBCentralManager!
    private let queue = DispatchQueue(label: "knuckled-ble-central")
    private let pipe = BlePipe()
    private var target: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var found: [(peripheral: CBPeripheral, name: String?)] = []
    private let foundLock = NSLock()
    private var powered = false
    private var powerError: BleError?
    private let stateSem = DispatchSemaphore(value: 0)
    private let eventSem = DispatchSemaphore(value: 0)
    private var event = false
    private var writeAcked = false
    private let writeSem = DispatchSemaphore(value: 0)
    private var discoveredUUIDs: Set<UUID> = []
    private var cancelled = false

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: queue)
        pipe.onWrite = { [weak self] data, mode in self?.send(data, mode: mode) }
    }

    func discover(timeout: TimeInterval = 5) throws -> [DeviceInfo] {
        guard waitPoweredOn() else { throw powerError ?? .bluetoothOff }
        foundLock.lock(); found = []; foundLock.unlock()
        manager.scanForPeripherals(withServices: [BleUUIDs.service], options: nil)
        Thread.sleep(forTimeInterval: timeout)
        manager.stopScan()
        foundLock.lock(); defer { foundLock.unlock() }
        return found.map { DeviceInfo(name: $0.name, address: $0.peripheral.identifier.uuidString) }
    }

    func connect(device: DeviceInfo, pin: String) throws -> GameLink {
        guard waitPoweredOn() else { throw powerError ?? .bluetoothOff }
        guard let uuid = UUID(uuidString: device.address),
              let peripheral = manager.retrievePeripherals(withIdentifiers: [uuid]).first
        else { throw BleError.peerLost }
        target = peripheral
        peripheral.delegate = self
        event = false
        manager.connect(peripheral, options: nil)
        guard waitEvent(timeout: 15) else { cleanup(); throw BleError.peerLost }
        event = false
        peripheral.discoverServices([BleUUIDs.service])
        guard waitEvent(timeout: 10) else { cleanup(); throw BleError.peerLost }
        guard let service = peripheral.services?.first(where: { $0.uuid == BleUUIDs.service }) else {
            cleanup(); throw BleError.peerLost
        }
        event = false
        peripheral.discoverCharacteristics([BleUUIDs.write, BleUUIDs.notify], for: service)
        guard waitEvent(timeout: 10) else { cleanup(); throw BleError.peerLost }
        guard let chars = service.characteristics,
              let write = chars.first(where: { $0.uuid == BleUUIDs.write }),
              let notify = chars.first(where: { $0.uuid == BleUUIDs.notify })
        else { cleanup(); throw BleError.peerLost }
        writeChar = write
        notifyChar = notify
        event = false
        peripheral.setNotifyValue(true, for: notify)
        guard waitEvent(timeout: 10) else { cleanup(); throw BleError.peerLost }
        pipe.mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        // Reliable handshake writes, then fast path for the game.
        pipe.writeMode = .withResponse
        let ok = Handshake.initiate(source: pipe, sink: pipe, pin: pin)
        pipe.writeMode = .withoutResponse
        guard ok else { cleanup(); throw BleError.handshakeFailed }
        return GameLinkCore(input: pipe, output: pipe)
    }

    func cancel() {
        cancelled = true
        if let target { manager.cancelPeripheralConnection(target) }
        pipe.close()
        eventSem.signal()
        writeSem.signal()
    }

    private func cleanup() {
        if let target { manager.cancelPeripheralConnection(target) }
        pipe.close()
    }

    private func waitPoweredOn() -> Bool {
        if CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted {
            powerError = .unauthorized
            return false
        }
        while true {
            if cancelled { return false }
            if powered { return true }
            if powerError != nil { return false }
            _ = stateSem.wait(timeout: .now() + 0.5)
        }
    }

    private func waitEvent(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !event {
            if cancelled { return false }
            if Date() > deadline { return false }
            _ = eventSem.wait(timeout: .now() + 0.2)
        }
        return true
    }

    private func send(_ data: Data, mode: CBCharacteristicWriteType) {
        guard let target, let writeChar else { return }
        if mode == .withResponse {
            writeAcked = false
            target.writeValue(data, for: writeChar, type: .withResponse)
            _ = writeSem.wait(timeout: .now() + 5)
        } else {
            target.writeValue(data, for: writeChar, type: .withoutResponse)
        }
    }
}

extension BleCentralClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            powered = true
            powerError = nil
        case .poweredOff:
            powered = false
            powerError = .bluetoothOff
        case .unauthorized:
            powered = false
            powerError = .unauthorized
        case .unsupported:
            powered = false
            powerError = .unsupported
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
        if CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted {
            powered = false
            powerError = .unauthorized
        }
        stateSem.signal()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        foundLock.lock()
        if !found.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            found.append((peripheral, peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)))
        }
        foundLock.unlock()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        event = true
        eventSem.signal()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        event = false
        eventSem.signal()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        pipe.close()
        eventSem.signal()
    }
}

extension BleCentralClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        event = (error == nil)
        eventSem.signal()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        event = (error == nil)
        eventSem.signal()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        event = (error == nil && characteristic.isNotifying)
        eventSem.signal()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == BleUUIDs.notify, let value = characteristic.value else { return }
        pipe.feed(value)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        writeAcked = (error == nil)
        writeSem.signal()
    }
}
