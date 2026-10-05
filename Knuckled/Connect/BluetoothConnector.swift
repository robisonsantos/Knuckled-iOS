import Foundation
import KnuckledCore

/// A peer device (Android parity: `DeviceInfo(name, address)`; iOS uses the
/// peripheral identifier string as the address).
struct DeviceInfo: Equatable {
    var name: String?
    var address: String
}

enum FakeConnectorError: Error, Equatable { case invalidPin, cancelled }

/// Blocking transport facade (Android parity: all three calls block and run
/// off the main thread; the real BLE connector implements the same shape).
/// `cancel()` unblocks an in-flight call; default no-op for transports that
/// complete immediately. ConnectionSession calls it from cancelCurrent()/
/// disconnect() before resetting state (mirrors Android resetForError).
protocol BluetoothConnector {
    func listen(pin: String) throws -> GameLink
    func connect(device: DeviceInfo, pin: String) throws -> GameLink
    func discover() throws -> [DeviceInfo]
    func cancel()
}

extension BluetoothConnector {
    func cancel() {}
}

/// Simulator/DEBUG transport mirroring Android's FakeBluetoothConnector:
/// fixed PIN 1234, one fake peer, loopback pairs with bots.
final class FakeConnector: BluetoothConnector {
    static let pin = "1234"
    static let fakeDevice = DeviceInfo(name: "Fake Peer", address: "00:11:22:33:44:55")

    /// Retained fake hosts (a host bot must stay alive for the session;
    /// mirrors Android holding peer references).
    private var hosts: [GameHost] = []
    private let cancelLock = NSLock()
    private var cancelled = false

    func cancel() {
        cancelLock.lock()
        cancelled = true
        cancelLock.unlock()
    }

    private func isCancelled() -> Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return cancelled
    }

    func listen(pin: String) throws -> GameLink {
        guard pin == Self.pin else { throw FakeConnectorError.invalidPin }
        cancelLock.lock()
        cancelled = false
        cancelLock.unlock()
        // Brief hosting beat so HostingView renders before the fake client
        // connects (mirrors real BLE latency; keeps the host UI test deterministic).
        // Interruptible in 0.1s slices so cancel() unblocks promptly.
        // (2s total keeps parity with Android's fake pacing; documented.)
        for _ in 0..<20 {
            if isCancelled() { throw FakeConnectorError.cancelled }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let (hostLink, clientLink) = InMemoryLinkPair.make()
        runFakeClient(clientLink)
        return hostLink
    }

    func connect(device: DeviceInfo, pin: String) throws -> GameLink {
        guard pin == Self.pin else { throw FakeConnectorError.invalidPin }
        let (clientLink, hostLink) = InMemoryLinkPair.make()
        hosts.append(runFakeHost(hostLink))
        return clientLink
    }

    func discover() throws -> [DeviceInfo] { [Self.fakeDevice] }
}
