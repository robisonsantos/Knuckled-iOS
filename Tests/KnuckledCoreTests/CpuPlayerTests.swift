import XCTest
@testable import KnuckledCore

final class CpuPlayerTests: XCTestCase {

    private func awaitingTurn(_ lastRoll: Int, mine: Grid, theirs: Grid, currentTurn: PlayerId = .CLIENT) -> GameState {
        GameState(
            hostName: "Host",
            clientName: CpuPlayer.name,
            status: .IN_PROGRESS,
            currentTurn: currentTurn,
            phase: .AWAITING_PLACEMENT,
            grid: [.HOST: theirs, .CLIENT: mine],
            lastRoll: lastRoll
        )
    }

    private func openColumns(_ state: GameState, _ player: PlayerId) -> Set<Int> {
        let grid = state.grid[player]!
        return Set(grid.indices.filter { !KnucklebonesRules.columnFull(grid, $0) })
    }

    private func emptyGrid() -> Grid { [[], [], []] }

    func testAlwaysReturnsALegalOpenColumn() {
        let mine: Grid = [[2, 3], [6], []]
        let theirs: Grid = [[1], [4, 4], [5, 5, 5]]
        let state = awaitingTurn(4, mine: mine, theirs: theirs)
        let chosen = CpuPlayer.chooseColumn(state)
        XCTAssertTrue(openColumns(state, .CLIENT).contains(chosen), "chosen \(chosen) must be open")
    }

    func testIsDeterministicForTheSameState() {
        let mine: Grid = [[3, 5], [2], []]
        let theirs: Grid = [[6], [], [1, 1]]
        let state = awaitingTurn(2, mine: mine, theirs: theirs)
        XCTAssertEqual(CpuPlayer.chooseColumn(state), CpuPlayer.chooseColumn(state))
    }

    func testDestroysTheOpponentsStrongSameValuePair() {
        let mine = emptyGrid()
        let theirs: Grid = [[6, 6], [], []]
        let state = awaitingTurn(6, mine: mine, theirs: theirs)
        XCTAssertEqual(CpuPlayer.chooseColumn(state), 0)
    }

    func testKeepsItsOwnPairTogetherToCompleteATriple() {
        let mine: Grid = [[5, 5], [], []]
        let theirs = emptyGrid()
        let state = awaitingTurn(5, mine: mine, theirs: theirs)
        XCTAssertEqual(CpuPlayer.chooseColumn(state), 0)
    }

    func testNeverPlacesIntoAFullColumn() {
        let mine: Grid = [[1, 2, 3], [], []]
        let theirs = emptyGrid()
        let state = awaitingTurn(6, mine: mine, theirs: theirs)
        let chosen = CpuPlayer.chooseColumn(state)
        XCTAssertNotEqual(chosen, 0, "chosen \(chosen) must not be the full column 0")
    }

    func testFillsTheBoardToWinWhenTheEndgameFavoursIt() {
        let mine: Grid = [[3, 3], [4, 4, 4], [2, 2]]
        let theirs: Grid = [[2, 2], [1], [1]]
        let state = awaitingTurn(3, mine: mine, theirs: theirs)
        XCTAssertEqual(CpuPlayer.chooseColumn(state), 0)
    }
}
