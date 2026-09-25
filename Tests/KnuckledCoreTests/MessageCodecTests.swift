import XCTest
@testable import KnuckledCore

final class MessageCodecTests: XCTestCase {

    func testSanitizeNameTrimsAndStripsControlChars() {
        XCTAssertEqual(MessageCodec.sanitizeName("  Alice\n "), "Alice")
        XCTAssertEqual(MessageCodec.sanitizeName("A\u{0} b"), "A b")
    }

    func testEncodeNameAndDecodeNameRoundTrip() {
        let encoded = MessageCodec.encodeName("  Zulo  ")
        XCTAssertEqual(encoded, "NAME:Zulo")
        XCTAssertEqual(MessageCodec.decodeName(encoded), "Zulo")
        XCTAssertNil(MessageCodec.decodeName("STATE:{}"))
    }

    func testRollAndRestartMarkersMatchExactly() {
        XCTAssertTrue(MessageCodec.isRoll(MessageCodec.encodeRoll()))
        XCTAssertTrue(MessageCodec.isRestart(MessageCodec.encodeRestart()))
        XCTAssertFalse(MessageCodec.isRoll("ROLL:0"))
        XCTAssertFalse(MessageCodec.isRestart("RESTARTING"))
    }

    func testEncodePlaceRoundTripsValidColumns() {
        for col in 0...2 {
            let encoded = MessageCodec.encodePlace(col)
            XCTAssertEqual(MessageCodec.decodePlace(encoded), col)
        }
    }

    func testDecodePlaceRejectsMalformedLines() {
        XCTAssertNil(MessageCodec.decodePlace("PLACE"))
        XCTAssertNil(MessageCodec.decodePlace("PLACE:abc"))
        XCTAssertNil(MessageCodec.decodePlace("PLACE:3"))
        XCTAssertNil(MessageCodec.decodePlace("ROLL"))
    }

    func testStateRoundTripsAllFieldsIncludingDestroyedRefs() throws {
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
        let decoded = MessageCodec.decodeState(MessageCodec.encodeState(state))
        XCTAssertEqual(decoded, state)
        XCTAssertNil(MessageCodec.decodeState("STATE:not-json"))
        XCTAssertNil(MessageCodec.decodeState("NAME:Host"))
    }

    func testPlacePrefixLengthIsUsedCorrectly() {
        XCTAssertEqual(MessageCodec.encodePlace(0), "PLACE:0")
        XCTAssertEqual(MessageCodec.encodePlace(2), "PLACE:2")
    }
}
