import XCTest
@testable import Knuckled
import KnuckledCore

private enum TestError: Error { case timeout }

final class GameSessionTests: XCTestCase {

    private func waitFor(_ condition: @autoclosure () -> Bool, timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw TestError.timeout }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func startedSession() throws -> GameSession {
        let session = GameSession()
        session.startSinglePlayer(
            name: "Tester",
            rollDelayMs: 0,
            rollValue: { 3 },
            firstPlayer: { .HOST },
            preRollDelayMs: 0,
            thinkDelay: { 0 }
        )
        try waitFor(session.state != nil, timeout: 10)
        return session
    }

    func testStartPublishesFirstState() throws {
        let session = try startedSession()
        let s = session.state!
        XCTAssertEqual(s.hostName, "Tester")
        XCTAssertEqual(s.clientName, "CPU")
        XCTAssertEqual(s.status, .IN_PROGRESS)
        XCTAssertEqual(s.currentTurn, .HOST)
        XCTAssertTrue(session.inGame)
        XCTAssertTrue(session.canRoll)
    }

    func testRollPlaceAndCpuAnswers() throws {
        let session = try startedSession()
        session.roll()
        try waitFor(session.state!.phase == .AWAITING_PLACEMENT, timeout: 10)
        XCTAssertEqual(session.state!.lastRoll, 3)
        session.place(0)
        try waitFor(session.state!.grid[.HOST]![0] == [3], timeout: 10)
        // CPU answers on its turn (think delays are 0 in this session)
        try waitFor(session.state!.currentTurn == .HOST, timeout: 10)
        XCTAssertEqual(session.state!.grid[.CLIENT]!.flatMap { $0 }.count, 1)
    }

    func testPlayAgainMidGameIsIgnored() throws {
        let session = try startedSession()
        let before = session.state!
        session.playAgain()
        XCTAssertEqual(session.state!, before)
    }

    func testDisconnectClearsState() throws {
        let session = try startedSession()
        session.disconnect()
        XCTAssertNil(session.state)
        XCTAssertFalse(session.inGame)
    }

    /// Deterministic destroy flow: rigged roll sequence forces a collision.
    /// Turn 1 (host): rolls 4, places col 0 → host [4]. Turn 1 (CPU): rolls 5,
    /// expectimax takes col 0 on the empty board (first-best tie-break).
    /// Turn 2 (host): rolls 5, places col 0 → destroys the CPU's 5. The
    /// published state must carry the destroy marker (visible through the
    /// CPU's think delay), and the boards must reflect the destruction.
    func testDestroyedMarkersFlowThroughSession() throws {
        var rolls = [4, 5, 5, 1, 2, 3]
        let session = GameSession()
        session.startSinglePlayer(
            name: "Tester",
            rollDelayMs: 0,
            rollValue: {
                let v = rolls.removeFirst()
                rolls.append(v)
                return v
            },
            firstPlayer: { .HOST },
            preRollDelayMs: 0,
            thinkDelay: { 5 }
        )
        try waitFor(session.state != nil, timeout: 10)

        session.roll()
        try waitFor(session.state!.phase == .AWAITING_PLACEMENT, timeout: 10)
        XCTAssertEqual(session.state!.lastRoll, 4)
        session.place(0)
        try waitFor(session.state!.currentTurn == .CLIENT, timeout: 10)
        XCTAssertEqual(session.state!.grid[.HOST]![0], [4])

        // CPU rolls 5 and (deterministically) takes col 0, then thinks 5s.
        try waitFor(session.state!.currentTurn == .HOST, timeout: 20)
        XCTAssertEqual(session.state!.grid[.CLIENT]![0], [5])

        session.roll()
        try waitFor(session.state!.phase == .AWAITING_PLACEMENT, timeout: 10)
        XCTAssertEqual(session.state!.lastRoll, 5)
        session.place(0)
        // The destroy marker must be published and visible through the CPU's
        // 5s think delay (it clears only at the next placement).
        try waitFor(!session.state!.destroyed.isEmpty, timeout: 10)
        let s = session.state!
        XCTAssertEqual(s.grid[.HOST]![0], [4, 5])
        XCTAssertEqual(s.grid[.CLIENT]![0], [])
        XCTAssertEqual(s.destroyed, [DieRef(player: .CLIENT, column: 0, value: 5)])
    }
}
