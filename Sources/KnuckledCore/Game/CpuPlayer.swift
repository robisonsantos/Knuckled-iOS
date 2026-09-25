import Foundation

/// Column picker for the already-rolled die that maximises expected final score.
public enum CpuPlayer {
    public static let name = "CPU"

    private static let win = 1_000_000.0
    private static let lockBonus = 0.10
    private static let riskWeight = 0.05

    public static func chooseColumn(_ state: GameState, me: PlayerId = .CLIENT) -> Int {
        let grid = state.grid[me] ?? []
        let open = grid.indices.filter { !KnucklebonesRules.columnFull(grid, $0) }
        if open.isEmpty { return 0 }
        let search = Search(me: me)
        var best = open[0]
        var bestValue = -Double.infinity
        for column in open {
            let after = KnucklebonesRules.place(state, me, column)
            let value = search.value(after, depth: depthLimit(state))
            if value > bestValue {
                bestValue = value
                best = column
            }
        }
        return best
    }

    /// Deeper search the closer the boards are to full.
    private static func depthLimit(_ state: GameState) -> Int {
        let placed = state.grid.values.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } }
        switch placed {
        case 12...: return 6
        case 6...: return 4
        default: return 3
        }
    }

    /// Expectimax: max nodes are the CPU's placements, min nodes the human's, chance nodes the die.
    private final class Search {
        private let me: PlayerId
        private var memo: [String: Double] = [:]

        init(me: PlayerId) {
            self.me = me
        }

        func value(_ state: GameState, depth: Int) -> Double {
            switch state.status {
            case .FINISHED: return state.winner == me ? CpuPlayer.win : -CpuPlayer.win
            case .DRAW: return 0
            case .IN_PROGRESS: return searchValue(state, depth: depth)
            }
        }

        private func searchValue(_ state: GameState, depth: Int) -> Double {
            if depth <= 0 { return evaluate(state) }
            let key = stateKey(state, depth: depth)
            if let cached = memo[key] { return cached }
            let result: Double
            switch state.phase {
            case .IDLE:
                let roller = state.currentTurn
                var sum = 0.0
                for v in 1...6 {
                    let rolled = KnucklebonesRules.completeRoll(KnucklebonesRules.beginRoll(state, roller), roller, v)
                    sum += value(rolled, depth: depth)
                }
                result = sum / 6.0
            case .AWAITING_PLACEMENT:
                let mover = state.currentTurn
                let moverGrid = state.grid[mover]!
                let open = moverGrid.indices.filter { !KnucklebonesRules.columnFull(moverGrid, $0) }
                let children = open.map { value(KnucklebonesRules.place(state, mover, $0), depth: depth - 1) }
                result = mover == me ? (children.max() ?? 0) : (children.min() ?? 0)
            case .ROLLING:
                result = evaluate(state)
            }
            memo[key] = result
            return result
        }

        private func evaluate(_ state: GameState) -> Double {
            let mine = state.grid[me]!
            let theirs = state.grid[state.opponentOf(me)]!
            var e = Double(KnucklebonesRules.totalScore(mine) - KnucklebonesRules.totalScore(theirs))
            for (i, column) in mine.enumerated() {
                if KnucklebonesRules.columnFull(mine, i) {
                    e += Double(KnucklebonesRules.columnScore(column)) * CpuPlayer.lockBonus
                }
                if !KnucklebonesRules.columnFull(theirs, i) {
                    var counts: [Int: Int] = [:]
                    for v in column { counts[v, default: 0] += 1 }
                    for (value, count) in counts where count >= 2 {
                        e -= Double(value * count * count) * CpuPlayer.riskWeight
                    }
                }
            }
            return e
        }

        private func stateKey(_ state: GameState, depth: Int) -> String {
            let host = state.grid[.HOST]!
            let client = state.grid[.CLIENT]!
            let lastRoll = state.lastRoll.map(String.init) ?? "null"
            return "\(depth)|\(state.currentTurn.rawValue)|\(state.phase.rawValue)|\(lastRoll)|"
                + host.map { $0.map(String.init).joined(separator: ",") }.joined(separator: ";")
                + "|" + client.map { $0.map(String.init).joined(separator: ",") }.joined(separator: ";")
        }
    }
}
