import XCTest
@testable import Knuckled
@testable import KnuckledCore

final class ConnectionSessionTests: XCTestCase {

    /// Cancellable blocking mock: proves cancel reaches the radio and that
    /// discover+connect share one connector instance within the session.
    final class MockConnector: BluetoothConnector {
        let enteredListen = DispatchSemaphore(value: 0)
        let releaseListen = DispatchSemaphore(value: 0)
        var cancelCalled = false
        var discoverDevices: [DeviceInfo] = []
        var connectDevices: [DeviceInfo] = []
        var retained: [GameLink] = []

        func listen(pin: String) throws -> GameLink {
            enteredListen.signal()
            _ = releaseListen.wait(timeout: .now() + 15)
            if cancelCalled { throw FakeConnectorError.cancelled }
            let (a, b) = InMemoryLinkPair.make()
            retained.append(b)
            return a
        }

        func connect(device: DeviceInfo, pin: String) throws -> GameLink {
            connectDevices.append(device)
            let (a, b) = InMemoryLinkPair.make()
            retained.append(b)
            return a
        }

        func discover() throws -> [DeviceInfo] { discoverDevices }

        func cancel() {
            cancelCalled = true
            releaseListen.signal()
        }
    }

    private func mockSession(_ mock: MockConnector) -> ConnectionSession {
        ConnectionSession(connector: mock)
    }

    private func waitFor(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 10) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw TestError.timeout }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func session() -> ConnectionSession {
        ConnectionSession(connector: FakeConnector())
    }

    func testHostFlowConnectsAsHost() throws {
        let connection = session()
        connection.playerName = "Host"
        connection.onHostClicked()
        if case .hosting(let pin) = connection.state {
            XCTAssertEqual(pin, FakeConnector.pin)
        } else {
            XCTFail("expected hosting, got \(connection.state)")
        }
        try waitFor(connection.isConnected, timeout: 10)
        if case .connected(_, let peer, let isHost) = connection.state {
            XCTAssertTrue(isHost)
            XCTAssertNil(peer)
        } else {
            XCTFail("expected connected, got \(connection.state)")
        }
    }

    func testBlankNameShowsErrorAndStays() {
        let connection = session()
        connection.playerName = "   "
        connection.onHostClicked()
        XCTAssertEqual(connection.errorText, "Enter your name")
        if case .start = connection.state {} else {
            XCTFail("expected start, got \(connection.state)")
        }
    }

    func testWrongPinReturnsToStartWithError() throws {
        let connection = session()
        connection.playerName = "Joiner"
        connection.onDiscoverClicked()
        try waitFor(!connection.foundDevices.isEmpty, timeout: 10)
        connection.onDeviceSelected(connection.foundDevices[0])
        connection.onPinEntered("0000")
        try waitFor(connection.isStart, timeout: 10)
        XCTAssertEqual(connection.errorText, "Wrong code. Try again.")
    }

    func testCancelHostingReturnsToStart() {
        let connection = session()
        connection.playerName = "Host"
        connection.onHostClicked()
        connection.cancelCurrent()
        XCTAssertTrue(connection.isStart)
        XCTAssertEqual(connection.hostPin, "")
    }

    func testDisconnectSetsStatus() throws {
        let connection = session()
        connection.playerName = "Host"
        connection.onHostClicked()
        try waitFor(connection.isConnected, timeout: 10)
        connection.disconnect()
        XCTAssertTrue(connection.isStart)
        XCTAssertEqual(connection.statusText, "Disconnected")
    }

    func testCancelHostingReachesRadioAndReturnsToStart() throws {
        let mock = MockConnector()
        let connection = mockSession(mock)
        connection.playerName = "Host"
        connection.onHostClicked()
        XCTAssertTrue(mock.enteredListen.wait(timeout: .now() + 10) == .success)
        connection.cancelCurrent()
        XCTAssertTrue(connection.isStart)
        XCTAssertTrue(mock.cancelCalled, "cancelCurrent must call cancel() on the active connector")
    }

    func testDiscoverThenConnectSharesConnector() throws {
        let mock = MockConnector()
        mock.discoverDevices = [DeviceInfo(name: "Peer", address: "AA:BB:CC:DD:EE:FF")]
        let connection = mockSession(mock)
        connection.playerName = "Joiner"
        connection.onDiscoverClicked()
        try waitFor(!connection.foundDevices.isEmpty, timeout: 10)
        connection.onDeviceSelected(connection.foundDevices[0])
        connection.onPinEntered("1234")
        try waitFor(connection.isConnected, timeout: 10)
        XCTAssertEqual(mock.connectDevices, [DeviceInfo(name: "Peer", address: "AA:BB:CC:DD:EE:FF")])
    }

    /// Instant non-fake transport: exercises the real (BLE) host path,
    /// which must use a random 4-digit PIN (never the fixed Fake PIN).
    final class InstantHostConnector: BluetoothConnector {
        var pins: [String] = []
        var retained: [GameLink] = []
        func listen(pin: String) throws -> GameLink {
            pins.append(pin)
            let (a, b) = InMemoryLinkPair.make()
            retained.append(b)
            return a
        }
        func connect(device: DeviceInfo, pin: String) throws -> GameLink {
            let (a, b) = InMemoryLinkPair.make()
            retained.append(b)
            return a
        }
        func discover() throws -> [DeviceInfo] { [] }
    }

    func testRealHostGeneratesRandomPins() {
        var pins: [String] = []
        for _ in 0..<20 {
            let connection = ConnectionSession(connector: InstantHostConnector())
            connection.playerName = "Host"
            connection.onHostClicked()
            if case .hosting(let pin) = connection.state {
                pins.append(pin)
            } else {
                XCTFail("expected hosting, got \(connection.state)")
            }
            connection.cancelCurrent()
        }
        XCTAssertEqual(pins.count, 20)
        for pin in pins {
            XCTAssertEqual(pin.count, 4, "PIN must be 4 digits, got \(pin)")
            XCTAssertTrue(pin.allSatisfy(\.isWholeNumber), "PIN must be numeric, got \(pin)")
        }
        XCTAssertGreaterThan(Set(pins).count, 1, "20 random PINs must yield at least 2 distinct values")
    }
}
