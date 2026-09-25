import XCTest
@testable import KnuckledCore

final class GameStateJSONTests: XCTestCase {

    /// Canonical STATE JSON produced by the Android app (kotlinx.serialization,
    /// encodeDefaults=true, explicitNulls=true). The Swift decoder must accept it.
    private let androidFixture = """
    {"hostName":"Host","clientName":"Client","status":"IN_PROGRESS","currentTurn":"CLIENT","phase":"AWAITING_PLACEMENT","grid":{"HOST":[[4,1,4],[],[]],"CLIENT":[[],[6],[]]},"winner":null,"lastRoll":6,"destroyed":[{"player":"CLIENT","column":0,"value":4},{"player":"CLIENT","column":0,"value":4}]}
    """

    func testDecodesAndroidFixture() throws {
        let state = try MessageCodec.decodeStateThrowing("STATE:" + androidFixture)
        XCTAssertEqual(state.hostName, "Host")
        XCTAssertEqual(state.clientName, "Client")
        XCTAssertEqual(state.status, .IN_PROGRESS)
        XCTAssertEqual(state.currentTurn, .CLIENT)
        XCTAssertEqual(state.phase, .AWAITING_PLACEMENT)
        XCTAssertEqual(state.grid[.HOST], [[4, 1, 4], [], []])
        XCTAssertEqual(state.grid[.CLIENT], [[], [6], []])
        XCTAssertNil(state.winner)
        XCTAssertEqual(state.lastRoll, 6)
        XCTAssertEqual(state.destroyed, [DieRef(player: .CLIENT, column: 0, value: 4),
                                         DieRef(player: .CLIENT, column: 0, value: 4)])
    }

    func testEncodedJSONCarriesAllFieldsIncludingNulls() throws {
        let state = KnucklebonesRules.reset(hostName: "Host", clientName: "Client", firstPlayer: .HOST)
        let json = MessageCodec.stateJSON(state)
        XCTAssertTrue(json.contains("\"hostName\":\"Host\""))
        XCTAssertTrue(json.contains("\"clientName\":\"Client\""))
        XCTAssertTrue(json.contains("\"status\":\"IN_PROGRESS\""))
        XCTAssertTrue(json.contains("\"currentTurn\":\"HOST\""))
        XCTAssertTrue(json.contains("\"phase\":\"IDLE\""))
        XCTAssertTrue(json.contains("\"grid\":{\"CLIENT\":[[],[],[]],\"HOST\":[[],[],[]]}"))
        XCTAssertTrue(json.contains("\"winner\":null"))
        XCTAssertTrue(json.contains("\"lastRoll\":null"))
        XCTAssertTrue(json.contains("\"destroyed\":[]"))
    }

    func testEncodeDecodeRoundTripPreservesEveryField() throws {
        let state = GameState(
            hostName: "Host",
            clientName: "Client",
            status: .IN_PROGRESS,
            currentTurn: .CLIENT,
            phase: .AWAITING_PLACEMENT,
            grid: [.HOST: [[4, 1, 4], [], []], .CLIENT: [[], [6], []]],
            lastRoll: 6,
            destroyed: [DieRef(player: .CLIENT, column: 0, value: 4), DieRef(player: .CLIENT, column: 0, value: 4)]
        )
        let roundTripped = try MessageCodec.decodeStateThrowing(MessageCodec.encodeState(state))
        XCTAssertEqual(roundTripped, state)
    }

    func testUnknownKeyIsRejected() {
        let payload = """
        {"hostName":"H","clientName":"C","status":"IN_PROGRESS","currentTurn":"HOST","phase":"IDLE","grid":{"HOST":[[],[],[]],"CLIENT":[[],[],[]]},"winner":null,"lastRoll":null,"destroyed":[],"bogus":1}
        """
        XCTAssertNil(MessageCodec.decodeState("STATE:" + payload))
    }
}
