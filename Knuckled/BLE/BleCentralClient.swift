import Foundation
import CoreBluetooth
import KnuckledCore

/// Client side: scans for the service, connects, subscribes, runs the PIN
/// handshake (reliable writes), returns a live GameLink. Blocking facade —
/// call off the CB queue (ConnectionSession backgrounds it).
///
/// Threading: CoreBluetooth delegate callbacks arrive on `queue`; the
/// blocking call runs on a session background thread. `stateLock` guards
/// powered/powerError/cancelled/event/failed across both. Timeout values
/// unchanged (discover 5s; connect 15s; services/chars/subscribe 10s).
/// Failure callbacks (didFailToConnect, error-bearing delegate results,
/// disconnect mid-handshake) set `failed` and signal `eventSem` so the
/// waiter fails fast instead of running out the full timeout.
final class BleCentralClient: NSObject {
    private var manager: CBCentralManager!
    private let queue = DispatchQueue(label: "knuckled-ble-central")
    private let pipe = BlePipe()
    private var target: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var found: [(peripheral: CBPeripheral, name: String?)] = []
    private let foundLock = NSLock()
    private let stateLock = NSLock()
    private var powered = false
    private var powerError: BleError?
    private let stateSem = DispatchSemaphore(value: 0)
    private let eventSem = DispatchSemaphore(value: 0)
    private var event = false
    private var failed = false
    private let writeSem = DispatchSemaphore(value: 0)
    private var cancelled = false

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: queue)
        pipe.onWrite = { [weak self] data, mode in self?.send(data, mode: mode) }
    }

    func discover(timeout: TimeInterval = 5) throws -> [DeviceInfo] {
        resetAttempt()
        guard waitPoweredOn() else { throw currentPowerError() ?? .bluetoothOff }
        foundLock.lock(); found = []; foundLock.unlock()
        manager.scanForPeripherals(withServices: [BleUUIDs.service], options: nil)
        defer { manager.stopScan() }
        // Interruptible scan window (was Thread.sleep): cancel() shortens it.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isCancelled() { throw BleError.cancelled }
            Thread.sleep(forTimeInterval: 0.2)
        }
        foundLock.lock(); defer { foundLock.unlock() }
        return found.map { DeviceInfo(name: $0.name, address: $0.peripheral.identifier.uuidString) }
    }

    func connect(device: DeviceInfo, pin: String) throws -> GameLink {
        resetAttempt()
        guard waitPoweredOn() else { throw currentPowerError() ?? .bluetoothOff }
        guard let uuid = UUID(uuidString: device.address),
              let peripheral = manager.retrievePeripherals(withIdentifiers: [uuid]).first
        else { throw BleError.peerLost }
        target = peripheral
        peripheral.delegate = self
        setEvent(false, failed: false)
        manager.connect(peripheral, options: nil)
        guard waitEvent(timeout: 15) else { cleanup(); throw lastError() }
        setEvent(false, failed: false)
        peripheral.discoverServices([BleUUIDs.service])
        guard waitEvent(timeout: 10) else { cleanup(); throw lastError() }
        guard let service = peripheral.services?.first(where: { $0.uuid == BleUUIDs.service }) else {
            cleanup(); throw BleError.peerLost
        }
        setEvent(false, failed: false)
        peripheral.discoverCharacteristics([BleUUIDs.write, BleUUIDs.notify], for: service)
        guard waitEvent(timeout: 10) else { cleanup(); throw lastError() }
        guard let chars = service.characteristics,
              let write = chars.first(where: { $0.uuid == BleUUIDs.write }),
              let notify = chars.first(where: { $0.uuid == BleUUIDs.notify })
        else { cleanup(); throw BleError.peerLost }
        writeChar = write
        notifyChar = notify
        setEvent(false, failed: false)
        peripheral.setNotifyValue(true, for: notify)
        guard waitEvent(timeout: 10) else { cleanup(); throw lastError() }
        pipe.mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        // Reliable handshake writes, then fast path for the game.
        pipe.writeMode = .withResponse
        let ok = Handshake.initiate(source: pipe, sink: pipe, pin: pin)
        pipe.writeMode = .withoutResponse
        guard ok else { cleanup(); throw BleError.handshakeFailed }
        return GameLinkCore(input: pipe, output: pipe)
    }

    func cancel() {
        stateLock.lock()
        cancelled = true
        let target = target
        stateLock.unlock()
        if let target { manager.cancelPeripheralConnection(target) }
        manager.stopScan()
        pipe.close()
        stateSem.signal()
        eventSem.signal()
        writeSem.signal()
    }

    private func cleanup() {
        stateLock.lock()
        let target = target
        stateLock.unlock()
        if let target { manager.cancelPeripheralConnection(target) }
        pipe.close()
    }

    /// Clears per-attempt state (incl. a stale cancel) at op start.
    private func resetAttempt() {
        stateLock.lock()
        cancelled = false
        event = false
        failed = false
        stateLock.unlock()
    }

    private func lastError() -> BleError {
        stateLock.lock()
        defer { stateLock.unlock() }
        if cancelled { return .cancelled }
        return .peerLost
    }

    private func waitPoweredOn() -> Bool {
        if CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted {
            stateLock.lock()
            powerError = .unauthorized
            stateLock.unlock()
            return false
        }
        while true {
            stateLock.lock()
            let done = cancelled
            let ok = powered
            let err = powerError
            stateLock.unlock()
            if done { return false }
            if ok { return true }
            if err != nil { return false }
            _ = stateSem.wait(timeout: .now() + 0.5)
        }
    }

    private func currentPowerError() -> BleError? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return powerError
    }

    private func isCancelled() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancelled
    }

    private func setEvent(_ value: Bool, failed: Bool) {
        stateLock.lock()
        event = value
        self.failed = failed
        stateLock.unlock()
    }

    private func waitEvent(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            stateLock.lock()
            let done = event
            let bad = failed || cancelled
            stateLock.unlock()
            if done { return true }
            if bad { return false }
            if Date() > deadline { return false }
            _ = eventSem.wait(timeout: .now() + 0.2)
        }
    }

    private func signalEvent(success: Bool) {
        stateLock.lock()
        event = success
        if !success { failed = true }
        stateLock.unlock()
        eventSem.signal()
    }

    private func signalFailure() {
        stateLock.lock()
        failed = true
        stateLock.unlock()
        eventSem.signal()
    }

    private func send(_ data: Data, mode: CBCharacteristicWriteType) {
        stateLock.lock()
        let target = target
        let writeChar = writeChar
        stateLock.unlock()
        guard let target, let writeChar else { return }
        if mode == .withResponse {
            target.writeValue(data, for: writeChar, type: .withResponse)
            _ = writeSem.wait(timeout: .now() + 5)
        } else {
            target.writeValue(data, for: writeChar, type: .withoutResponse)
        }
    }
}

extension BleCentralClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        stateLock.lock()
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
        stateLock.unlock()
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
        signalEvent(success: true)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        signalFailure()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        pipe.close()
        signalFailure()
    }
}

extension BleCentralClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        signalEvent(success: error == nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        signalEvent(success: error == nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        signalEvent(success: error == nil && characteristic.isNotifying)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == BleUUIDs.notify, let value = characteristic.value else { return }
        pipe.feed(value)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        writeSem.signal()
    }
}
