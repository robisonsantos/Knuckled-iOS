import Foundation

/// Authoritative game owner (the host side). Owns state, validates every move,
/// sleeps `rollDelayMs` mid-roll, and broadcasts STATE after every change.
public final class GameHost {
    private let link: GameLink
    private let hostName: String
    private let rollValue: () -> Int
    private let rollDelayMs: Int
    private let firstPlayer: () -> PlayerId
    /// Invoked on the caller's thread (reader thread for peer lines); UI observers must dispatch to main.
    private let onState: (GameState) -> Void

    private let lock = NSLock()
    private var _state: GameState
    private var first: PlayerId?

    /// Current state. Serialized with an internal lock: safe to read from test/UI
    /// threads while link callbacks mutate it. `rollValue`/`firstPlayer` closures
    /// must be non-reentrant (must not call back into this host).
    public var state: GameState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    /// - Parameters rollValue, firstPlayer: invoked with the internal lock held; must not re-enter this host.
    public init(link: GameLink,
                hostName: String,
                rollValue: @escaping () -> Int = { Int.random(in: 1...6) },
                rollDelayMs: Int = 2000,
                firstPlayer: @escaping () -> PlayerId = { Bool.random() ? .HOST : .CLIENT },
                onState: @escaping (GameState) -> Void = { _ in }) {
        self.link = link
        self.hostName = hostName
        self.rollValue = rollValue
        self.rollDelayMs = rollDelayMs
        self.firstPlayer = firstPlayer
        self.onState = onState
        self._state = KnucklebonesRules.reset(hostName: hostName, clientName: "?", firstPlayer: .HOST)
    }

    public func connect() {
        link.onLine = { [weak self] line in self?.onLine(line) }
    }

    private func onLine(_ line: String) {
        if let name = MessageCodec.decodeName(line) {
            lock.lock()
            first = firstPlayer()
            _state = KnucklebonesRules.reset(hostName: hostName, clientName: MessageCodec.sanitizeName(name), firstPlayer: first!)
            let snapshot = _state
            lock.unlock()
            publish(snapshot)
        } else if MessageCodec.isRoll(line) {
            rollFor(.CLIENT)
        } else if let column = MessageCodec.decodePlace(line) {
            placeFor(.CLIENT, column)
        } else if MessageCodec.isRestart(line) {
            restart()
        }
    }

    public func hostRoll() {
        rollFor(.HOST)
    }

    public func hostPlace(_ column: Int) {
        placeFor(.HOST, column)
    }

    private func rollFor(_ player: PlayerId) {
        lock.lock()
        guard KnucklebonesRules.canRoll(_state, player) else { lock.unlock(); return }
        _state = KnucklebonesRules.beginRoll(_state, player)
        let rolling = _state
        lock.unlock()
        publish(rolling)
        Thread.sleep(forTimeInterval: Double(rollDelayMs) / 1000.0)
        lock.lock()
        // Aborted roll: a reset/restart already published newer state; do not publish.
        guard _state.phase == .ROLLING && _state.currentTurn == player else { lock.unlock(); return }
        _state = KnucklebonesRules.completeRoll(_state, player, rollValue())
        let done = _state
        lock.unlock()
        publish(done)
    }

    private func placeFor(_ player: PlayerId, _ column: Int) {
        lock.lock()
        guard KnucklebonesRules.canPlace(_state, player, column) else { lock.unlock(); return }
        _state = KnucklebonesRules.place(_state, player, column)
        let snapshot = _state
        lock.unlock()
        publish(snapshot)
    }

    public func restart() {
        lock.lock()
        guard KnucklebonesRules.canRestart(_state) else { lock.unlock(); return }
        let firstPlayerNow = first ?? firstPlayer()
        first = firstPlayerNow
        _state = KnucklebonesRules.reset(hostName: _state.hostName, clientName: _state.clientName, firstPlayer: firstPlayerNow)
        let snapshot = _state
        lock.unlock()
        publish(snapshot)
    }

    private func publish(_ snapshot: GameState) {
        try? link.send(MessageCodec.encodeState(snapshot))
        onState(snapshot)
    }
}
