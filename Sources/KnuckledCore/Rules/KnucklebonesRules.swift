import Foundation

public enum KnucklebonesRules {
    public static let columns = 3
    public static let columnSize = 3

    public static func emptyGrid() -> Grid {
        [Column](repeating: [], count: columns)
    }

    public static func reset(hostName: String, clientName: String, firstPlayer: PlayerId) -> GameState {
        GameState(
            hostName: hostName,
            clientName: clientName,
            status: .IN_PROGRESS,
            currentTurn: firstPlayer,
            phase: .IDLE,
            grid: [.HOST: emptyGrid(), .CLIENT: emptyGrid()],
            winner: nil,
            lastRoll: nil,
            destroyed: []
        )
    }

    /// value × count²: count dice, each worth value×count.
    public static func columnScore(_ column: Column) -> Int {
        var counts: [Int: Int] = [:]
        for value in column { counts[value, default: 0] += 1 }
        return counts.reduce(0) { $0 + $1.key * $1.value * $1.value }
    }

    public static func totalScore(_ grid: Grid) -> Int {
        grid.map(columnScore).reduce(0, +)
    }

    public static func columnFull(_ grid: Grid, _ column: Int) -> Bool {
        column < grid.count ? grid[column].count >= columnSize : false
    }

    public static func canRoll(_ state: GameState, _ player: PlayerId) -> Bool {
        state.status == .IN_PROGRESS && state.phase == .IDLE && state.currentTurn == player
    }

    public static func beginRoll(_ state: GameState, _ player: PlayerId) -> GameState {
        precondition(canRoll(state, player), "cannot begin roll for \(player)")
        return GameState(
            hostName: state.hostName, clientName: state.clientName,
            status: state.status, currentTurn: state.currentTurn,
            phase: .ROLLING, grid: state.grid,
            winner: state.winner, lastRoll: state.lastRoll, destroyed: state.destroyed
        )
    }

    public static func completeRoll(_ state: GameState, _ player: PlayerId, _ value: Int) -> GameState {
        precondition(state.phase == .ROLLING && state.currentTurn == player, "invalid completeRoll")
        precondition((1...6).contains(value), "die out of range: \(value)")
        return GameState(
            hostName: state.hostName, clientName: state.clientName,
            status: state.status, currentTurn: state.currentTurn,
            phase: .AWAITING_PLACEMENT, grid: state.grid,
            winner: state.winner, lastRoll: value, destroyed: state.destroyed
        )
    }

    public static func canPlace(_ state: GameState, _ player: PlayerId, _ column: Int) -> Bool {
        guard let grid = state.grid[player] else { return false }
        return state.phase == .AWAITING_PLACEMENT
            && state.currentTurn == player
            && column < grid.count
            && !columnFull(grid, column)
    }

    public static func place(_ state: GameState, _ player: PlayerId, _ column: Int) -> GameState {
        precondition(canPlace(state, player, column), "cannot place for \(player) in \(column)")
        guard let value = state.lastRoll else {
            preconditionFailure("no roll to place")
        }
        let opponent = state.opponentOf(player)

        var grid = state.grid
        var mine = grid[player]!
        mine[column] = mine[column] + [value]
        grid[player] = mine

        var destroyed: [DieRef] = []
        var theirs = grid[opponent]!
        let theirColumn = theirs[column]
        if theirColumn.contains(value) {
            theirs[column] = theirColumn.filter { $0 != value }
            let count = theirColumn.filter { $0 == value }.count
            for _ in 0..<count {
                destroyed.append(DieRef(player: opponent, column: column, value: value))
            }
            grid[opponent] = theirs
        }

        let boardFull = grid[player]!.allSatisfy { $0.count >= columnSize }
        var base = GameState(
            hostName: state.hostName, clientName: state.clientName,
            status: state.status, currentTurn: state.currentTurn,
            phase: .IDLE, grid: grid,
            winner: nil, lastRoll: nil, destroyed: destroyed
        )
        if !boardFull {
            base.currentTurn = opponent
            return base
        }

        let mineScore = totalScore(grid[player]!)
        let theirsScore = totalScore(grid[opponent]!)
        if mineScore == theirsScore {
            base.status = .DRAW
        } else if mineScore > theirsScore {
            base.status = .FINISHED
            base.winner = player
        } else {
            base.status = .FINISHED
            base.winner = opponent
        }
        return base
    }

    public static func canRestart(_ state: GameState) -> Bool {
        state.status != .IN_PROGRESS
    }
}
