import Foundation

/// Monotonic thread-safe counter (mirrors Android's AtomicInteger).
public final class Counter {
    private let lock = NSLock()
    private var n = 0
    public init() {}
    public func increment() { lock.lock(); n += 1; lock.unlock() }
    public var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

public enum FakeGamePeer {
    public static let name = "FakePeer"
    public static let pin = "1234"
    public static let hostName = "FakeHost"
    public static let reactDelaySeconds: Double = 0.15

    public static func firstOpenColumn(_ grid: Grid) -> Int {
        grid.indices.first { !KnucklebonesRules.columnFull(grid, $0) } ?? 0
    }
}

/// Runs a short delay on a background queue, then executes block (Kotlin's `delayed`).
public func delayed(_ delaySeconds: Double, _ block: @escaping () -> Void) {
    DispatchQueue.global().asyncAfter(deadline: .now() + delaySeconds) {
        block()
    }
}

/// Bot playing the client side: sends NAME, rolls on its turn, places in the first open column.
public func runFakeClient(_ link: GameLink) {
    link.onLine = { [weak link] line in
        guard let link else { return }
        guard let state = MessageCodec.decodeState(line) else { return }
        if KnucklebonesRules.canRoll(state, .CLIENT) {
            delayed(FakeGamePeer.reactDelaySeconds) { try? link.send(MessageCodec.encodeRoll()) }
        }
        if state.phase == .AWAITING_PLACEMENT && state.currentTurn == .CLIENT {
            guard let grid = state.grid[.CLIENT] else { return }
            let column = FakeGamePeer.firstOpenColumn(grid)
            delayed(FakeGamePeer.reactDelaySeconds) { try? link.send(MessageCodec.encodePlace(column)) }
        }
    }
    try? link.send(MessageCodec.encodeName(FakeGamePeer.name))
}

/// Bot playing the host side via a GameHost (used when the app connects as client in fake mode).
public func runFakeHost(_ link: GameLink) -> GameHost {
    let counter = Counter()
    var host: GameHost!
    host = GameHost(
        link: link,
        hostName: FakeGamePeer.hostName,
        rollValue: { counter.increment(); return (counter.value % 6) + 1 },
        rollDelayMs: 50,
        onState: { [weak host] state in
            guard let host else { return }
            if KnucklebonesRules.canRoll(state, .HOST) {
                delayed(0.05) { host.hostRoll() }
            }
            if state.phase == .AWAITING_PLACEMENT && state.currentTurn == .HOST {
                if let grid = state.grid[.HOST] {
                    let column = FakeGamePeer.firstOpenColumn(grid)
                    delayed(0.05) { host.hostPlace(column) }
                }
            }
        }
    )
    host.connect()
    return host
}
