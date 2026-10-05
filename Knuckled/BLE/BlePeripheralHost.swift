import Foundation
import CoreBluetooth
import KnuckledCore

/// Host side: advertises the service, waits for one subscriber, runs the PIN
/// handshake over the byte pipe, returns a live GameLink. Blocking facade —
/// call off the CB queue (ConnectionSession backgrounds it).
///
/// Threading: CoreBluetooth delegate callbacks arrive on `queue`; the
/// blocking call runs on a session background thread. `stateLock` guards
/// powered/powerError/cancelled across both. Timeout/poll values unchanged.
final class BlePeripheralHost: NSObject {
    private var manager: CBPeripheralManager!
    private let queue = DispatchQueue(label: "knuckled-ble-peripheral")
    private let pipe = BlePipe()
    private var notifyChar: CBMutableCharacteristic!
    private var subscriber: CBCentral?
    private let stateLock = NSLock()
    private var powered = false
    private var powerError: BleError?
    private let stateSem = DispatchSemaphore(value: 0)
    private let subscribedSem = DispatchSemaphore(value: 0)
    private var cancelled = false

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: queue)
        pipe.onWrite = { [weak self] data, _ in self?.notify(data) }
    }

    func listen(pin: String) throws -> GameLink {
        guard waitPoweredOn() else { throw currentPowerError() ?? .bluetoothOff }
        let service = CBMutableService(type: BleUUIDs.service, primary: true)
        let write = CBMutableCharacteristic(
            type: BleUUIDs.write,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        notifyChar = CBMutableCharacteristic(
            type: BleUUIDs.notify,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        service.characteristics = [write, notifyChar]
        manager.removeAllServices()
        manager.add(service)
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BleUUIDs.service],
            CBAdvertisementDataLocalNameKey: BleUUIDs.localName,
        ])
        while true {
            if isCancelled() { stop(); throw BleError.cancelled }
            if subscribedSem.wait(timeout: .now() + 0.2) == .success { break }
            if !isUsable() { stop(); throw currentPowerError() ?? .peerLost }
        }
        manager.stopAdvertising()
        if let sub = currentSubscriber() {
            pipe.mtu = sub.maximumUpdateValueLength
        }
        guard Handshake.accept(source: pipe, sink: pipe, expectedPin: pin) else {
            pipe.close()
            stop()
            throw BleError.handshakeFailed
        }
        return GameLinkCore(input: pipe, output: pipe)
    }

    func cancel() {
        stateLock.lock()
        cancelled = true
        stateLock.unlock()
        pipe.close()
        stop()
        stateSem.signal()
        subscribedSem.signal()
    }

    private func stop() {
        manager.stopAdvertising()
        manager.removeAllServices()
    }

    private func waitPoweredOn() -> Bool {
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

    private func isUsable() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return powered && powerError == nil && !cancelled
    }

    private func setPowerState(powered: Bool, error: BleError?) {
        stateLock.lock()
        self.powered = powered
        self.powerError = error
        stateLock.unlock()
        stateSem.signal()
    }

    private func notify(_ data: Data) {
        while true {
            if isCancelled() || currentSubscriber() == nil { return }
            if manager.updateValue(data, for: notifyChar, onSubscribedCentrals: nil) { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private func currentSubscriber() -> CBCentral? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return subscriber
    }

    private func setSubscriber(_ central: CBCentral?) {
        stateLock.lock()
        subscriber = central
        stateLock.unlock()
    }
}

extension BlePeripheralHost: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            setPowerState(powered: true, error: nil)
        case .poweredOff:
            setPowerState(powered: false, error: .bluetoothOff)
        case .unauthorized:
            setPowerState(powered: false, error: .unauthorized)
        case .unsupported:
            setPowerState(powered: false, error: .unsupported)
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
        if CBPeripheralManager.authorization == .denied || CBPeripheralManager.authorization == .restricted {
            setPowerState(powered: false, error: .unauthorized)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if characteristic.uuid == BleUUIDs.notify {
            setSubscriber(central)
            subscribedSem.signal()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        stateLock.lock()
        let current = subscriber
        stateLock.unlock()
        if current?.identifier == central.identifier {
            setSubscriber(nil)
        }
        pipe.close()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            pipe.feed(request.value ?? Data())
            peripheral.respond(to: request, withResult: .success)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        request.value = Data()
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // The notify() spin loop re-attempts; nothing to do here.
    }
}
