import XCTest
@testable import KnuckledCore

final class KnucklebonesRulesTests: XCTestCase {

    private func hostTurn() -> GameState {
        KnucklebonesRules.reset(hostName: "Host", clientName: "Client", firstPlayer: .HOST)
    }

    private func rolled(_ state: GameState, value: Int = 3) -> GameState {
        let begun = KnucklebonesRules.beginRoll(state, state.currentTurn)
        return KnucklebonesRules.completeRoll(begun, begun.currentTurn, value)
    }

    func testResetStartsAnEmptyInProgressGameWithGivenFirstPlayer() {
        let s = KnucklebonesRules.reset(hostName: "Host", clientName: "Client", firstPlayer: .CLIENT)
        XCTAssertEqual(s.status, .IN_PROGRESS)
        XCTAssertEqual(s.currentTurn, .CLIENT)
        XCTAssertEqual(s.phase, .IDLE)
        XCTAssertNil(s.winner)
        XCTAssertNil(s.lastRoll)
        XCTAssertTrue(s.destroyed.isEmpty)
        for player in PlayerId.allCases {
            XCTAssertEqual(s.grid[player]!.count, 3)
            for column in s.grid[player]! {
                XCTAssertTrue(column.isEmpty)
            }
        }
    }

    func testSingleDieInAColumnScoresItsValue() {
        XCTAssertEqual(KnucklebonesRules.columnScore([1]), 1)
        XCTAssertEqual(KnucklebonesRules.columnScore([6]), 6)
    }

    func testPairOfSameValueMultipliesByTwo() {
        XCTAssertEqual(KnucklebonesRules.columnScore([3, 3]), 12)
        XCTAssertEqual(KnucklebonesRules.columnScore([4, 4]), 16)
    }

    func testTripleOfSameValueMultipliesByThree() {
        XCTAssertEqual(KnucklebonesRules.columnScore([1, 1, 1]), 9)
        XCTAssertEqual(KnucklebonesRules.columnScore([6, 6, 6]), 54)
    }

    func testMixedColumnScoresEachValueByItsOwnCountOrderIrrelevant() {
        XCTAssertEqual(KnucklebonesRules.columnScore([4, 1, 4]), 17)
        XCTAssertEqual(KnucklebonesRules.columnScore([1, 4, 4]), 17)
    }

    func testMultiColumnGridSumsColumnScores() {
        let grid: Grid = [[4, 1, 4], [3, 3], []]
        XCTAssertEqual(KnucklebonesRules.totalScore(grid), 17 + 12)
    }

    func testColumnFullReflectsCapacity() {
        XCTAssertFalse(KnucklebonesRules.columnFull([[1, 2], [], []], 0))
        XCTAssertTrue(KnucklebonesRules.columnFull([[1, 2, 3], [], []], 0))
        XCTAssertFalse(KnucklebonesRules.columnFull([[], [], []], 0))
    }

    func testCanRollOnlyDuringIdleOnSendersTurn() {
        let s = hostTurn()
        XCTAssertTrue(KnucklebonesRules.canRoll(s, .HOST))
        XCTAssertFalse(KnucklebonesRules.canRoll(s, .CLIENT))
        let playing = KnucklebonesRules.beginRoll(s, .HOST)
        XCTAssertFalse(KnucklebonesRules.canRoll(playing, .HOST))
    }

    func testCompleteRollMovesToAwaitingPlacementAndRecordsTheValue() {
        let after = rolled(hostTurn(), value: 5)
        XCTAssertEqual(after.phase, .AWAITING_PLACEMENT)
        XCTAssertEqual(after.lastRoll, 5)
        XCTAssertTrue(after.grid[.HOST]!.flatMap { $0 }.isEmpty)
    }

    func testCanPlaceRestrictedToTheRollerAwaitingPlacementAndNonFullColumn() {
        let s = rolled(hostTurn(), value: 4)
        XCTAssertTrue(KnucklebonesRules.canPlace(s, .HOST, 0))
        XCTAssertFalse(KnucklebonesRules.canPlace(s, .CLIENT, 0))
        XCTAssertFalse(KnucklebonesRules.canPlace(s, .HOST, 3))
        let idle = KnucklebonesRules.reset(hostName: "Host", clientName: "Client", firstPlayer: .HOST)
        XCTAssertFalse(KnucklebonesRules.canPlace(idle, .HOST, 0))
    }

    func testPlacingAddsDieToChosenColumnAndEndsTheTurn() {
        let s = rolled(hostTurn(), value: 4)
        let after = KnucklebonesRules.place(s, .HOST, 1)
        XCTAssertEqual(after.grid[.HOST]![1], [4])
        XCTAssertEqual(after.currentTurn, .CLIENT)
        XCTAssertEqual(after.phase, .IDLE)
        XCTAssertNil(after.lastRoll)
    }

    func testPlacedDieDestroysMatchingDiceInOpponentsSameColumnOnly() {
        let built = GameState(
            hostName: "Host", clientName: "Client",
            status: .IN_PROGRESS, currentTurn: .HOST,
            phase: .AWAITING_PLACEMENT,
            grid: [.HOST: [[4, 1], [], []],
                   .CLIENT: [[3, 3], [], [3]]],
            lastRoll: 3
        )
        let after = KnucklebonesRules.place(built, .HOST, 0)
        XCTAssertEqual(after.grid[.HOST]![0], [4, 1, 3])
        XCTAssertEqual(after.grid[.CLIENT]![0], [])
        XCTAssertEqual(after.grid[.CLIENT]![2], [3])
        XCTAssertEqual(after.destroyed,
                       [DieRef(player: .CLIENT, column: 0, value: 3),
                        DieRef(player: .CLIENT, column: 0, value: 3)])
    }

    func testOpponentDiceOfOtherValuesSurvive() {
        let built = GameState(
            hostName: "Host", clientName: "Client",
            status: .IN_PROGRESS, currentTurn: .HOST,
            phase: .AWAITING_PLACEMENT,
            grid: [.HOST: [[], [], []],
                   .CLIENT: [[2, 3, 4], [], []]],
            lastRoll: 3
        )
        let after = KnucklebonesRules.place(built, .HOST, 0)
        XCTAssertEqual(after.grid[.CLIENT]![0], [2, 4])
    }

    func testGameEndsWhenAPlayerFillsTheirBoardAndHigherScoreWins() {
        let built2 = GameState(
            hostName: "Host", clientName: "Client",
            status: .IN_PROGRESS, currentTurn: .HOST,
            phase: .AWAITING_PLACEMENT,
            grid: [.HOST: [[3, 3, 3], [2, 2], [1, 1, 1]],
                   .CLIENT: [[], [], []]],
            lastRoll: 2
        )
        let after2 = KnucklebonesRules.place(built2, .HOST, 1)
        XCTAssertEqual(after2.status, .FINISHED)
        XCTAssertEqual(after2.winner, .HOST)
    }

    func testFillingPlayerCanStillLoseOnScore() {
        let built = GameState(
            hostName: "Host", clientName: "Client",
            status: .IN_PROGRESS, currentTurn: .HOST,
            phase: .AWAITING_PLACEMENT,
            grid: [.HOST: [[1, 1], [1, 1, 1], [1, 1, 1]],
                   .CLIENT: [[6, 6, 6], [6, 6, 6], [6, 6, 6]]],
            lastRoll: 1
        )
        let after = KnucklebonesRules.place(built, .HOST, 0)
        XCTAssertEqual(after.status, .FINISHED)
        XCTAssertEqual(after.winner, .CLIENT)
    }

    func testEqualScoresAtFullBoardProduceADraw() {
        let built = GameState(
            hostName: "Host", clientName: "Client",
            status: .IN_PROGRESS, currentTurn: .HOST,
            phase: .AWAITING_PLACEMENT,
            grid: [.HOST: [[2, 2], [1, 1, 1], [1, 1, 1]],
                   .CLIENT: [[3, 3, 3], [1, 1, 1], []]],
            lastRoll: 2
        )
        let after = KnucklebonesRules.place(built, .HOST, 0)
        XCTAssertEqual(after.status, .DRAW)
        XCTAssertNil(after.winner)
    }

    func testCanRestartOnlyAfterFinishedOrDraw() {
        XCTAssertFalse(KnucklebonesRules.canRestart(hostTurn()))
        XCTAssertTrue(KnucklebonesRules.canRestart(hostTurn().copy(status: .FINISHED, winner: .HOST)))
        XCTAssertTrue(KnucklebonesRules.canRestart(hostTurn().copy(status: .DRAW)))
    }
}
