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
}
