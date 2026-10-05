import Foundation
import KnuckledCore

/// Real radio transport behind the same blocking facade as the fake.
///
/// Lifetime: one shared BleCentralClient serves discover+connect so the
/// connect-after-discover peer resolves against the same CBCentralManager
/// that scanned (retrievePeripherals guarantee; no rescan needed on the
/// happy path — a stale identifier surfaces as BleError.peerLost, and the
/// user rescans from Discover). The active host is retained here (not per
/// call) so its CBPeripheralManager — and the GATT service the peer is
/// connected to — stays alive for the session, and so cancel() can reach
/// an in-flight listen/connect. Next listen/connect replaces the previous
/// handle; cancel() unblocks either and the session resets to Start.
final class BleConnector: BluetoothConnector {
    private let stateLock = NSLock()
    private var central: BleCentralClient?
    private var host: BlePeripheralHost?

    func listen(pin: String) throws -> GameLink {
        let h = BlePeripheralHost()
        stateLock.lock()
        host = h
        stateLock.unlock()
        return try h.listen(pin: pin)
    }

    func connect(device: DeviceInfo, pin: String) throws -> GameLink {
        stateLock.lock()
        if central == nil { central = BleCentralClient() }
        let c = central!
        stateLock.unlock()
        return try c.connect(device: device, pin: pin)
    }

    func discover() throws -> [DeviceInfo] {
        stateLock.lock()
        if central == nil { central = BleCentralClient() }
        let c = central!
        stateLock.unlock()
        return try c.discover()
    }

    func cancel() {
        stateLock.lock()
        let h = host
        let c = central
        stateLock.unlock()
        h?.cancel()
        c?.cancel()
    }
}
