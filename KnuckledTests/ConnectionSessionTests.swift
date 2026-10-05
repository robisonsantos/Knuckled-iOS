import XCTest
@testable import Knuckled
@testable import KnuckledCore

final class ConnectionSessionTests: XCTestCase {

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
}
