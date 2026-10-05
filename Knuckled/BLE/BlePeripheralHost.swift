import Foundation
import CoreBluetooth
import KnuckledCore

/// Host side: advertises the service, waits for one subscriber, runs the PIN
/// handshake over the byte pipe, returns a live GameLink. Blocking facade —
/// call off the CB queue (ConnectionSession backgrounds it).
final class BlePeripheralHost: NSObject {
    private var manager: CBPeripheralManager!
    private let queue = DispatchQueue(label: "knuckled-ble-peripheral")
    private let pipe = BlePipe()
    private var notifyChar: CBMutableCharacteristic!
    private var subscriber: CBCentral?
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
        guard waitPoweredOn() else { throw powerError ?? .bluetoothOff }
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
            if cancelled { stop(); throw BleError.cancelled }
            if subscribedSem.wait(timeout: .now() + 0.2) == .success { break }
            if !isUsable() { stop(); throw powerError ?? .peerLost }
        }
        manager.stopAdvertising()
        if let sub = subscriber {
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
        cancelled = true
        pipe.close()
        stop()
    }

    private func stop() {
        manager.stopAdvertising()
        manager.removeAllServices()
    }

    private func waitPoweredOn() -> Bool {
        while true {
            if cancelled { return false }
            if powered { return true }
            if powerError != nil { return false }
            _ = stateSem.wait(timeout: .now() + 0.5)
        }
    }

    private func isUsable() -> Bool { powered && powerError == nil && !cancelled }

    private func notify(_ data: Data) {
        while true {
            if pipeClosed() || subscriber == nil { return }
            if manager.updateValue(data, for: notifyChar, onSubscribedCentrals: nil) { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private func pipeClosed() -> Bool {
        // Best-effort: a closed pipe means teardown is underway.
        // (BlePipe has no public isClosed; the reader thread EOFs and the
        // link layer reports disconnect — this just stops the spin.)
        return cancelled
    }
}

extension BlePeripheralHost: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
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
        if CBPeripheralManager.authorization == .denied || CBPeripheralManager.authorization == .restricted {
            powered = false
            powerError = .unauthorized
        }
        stateSem.signal()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if characteristic.uuid == BleUUIDs.notify {
            subscriber = central
            subscribedSem.signal()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if subscriber?.identifier == central.identifier {
            subscriber = nil
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
