import Foundation
import KnuckledCore

/// A peer device (Android parity: `DeviceInfo(name, address)`; iOS uses the
/// peripheral identifier string as the address).
struct DeviceInfo: Equatable {
    var name: String?
    var address: String
}

enum FakeConnectorError: Error { case invalidPin }

/// Blocking transport facade (Android parity: all three calls block and run
/// off the main thread; the real BLE connector implements the same shape).
protocol BluetoothConnector {
    func listen(pin: String) throws -> GameLink
    func connect(device: DeviceInfo, pin: String) throws -> GameLink
    func discover() throws -> [DeviceInfo]
}

/// Simulator/DEBUG transport mirroring Android's FakeBluetoothConnector:
/// fixed PIN 1234, one fake peer, loopback pairs with bots.
final class FakeConnector: BluetoothConnector {
    static let pin = "1234"
    static let fakeDevice = DeviceInfo(name: "Fake Peer", address: "00:11:22:33:44:55")

    /// Retained fake hosts (a host bot must stay alive for the session;
    /// mirrors Android holding peer references).
    private var hosts: [GameHost] = []

    func listen(pin: String) throws -> GameLink {
        guard pin == Self.pin else { throw FakeConnectorError.invalidPin }
        // Brief hosting beat so HostingView renders before the fake client
        // connects (mirrors real BLE latency; keeps the host UI test deterministic).
        Thread.sleep(forTimeInterval: 2)
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
