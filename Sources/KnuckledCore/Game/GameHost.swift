import Foundation

/// Authoritative game owner (the host side). Owns state, validates every move,
/// sleeps `rollDelayMs` mid-roll, and broadcasts STATE after every change.
public final class GameHost {
    private let link: GameLink
    private let hostName: String
    private let rollValue: () -> Int
    private let rollDelayMs: Int
    private let firstPlayer: () -> PlayerId
    private let onState: (GameState) -> Void

    private var first: PlayerId?
    public private(set) var state: GameState

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
        self.state = KnucklebonesRules.reset(hostName: hostName, clientName: "?", firstPlayer: .HOST)
    }

    public func connect() {
        link.onLine = { [weak self] line in self?.onLine(line) }
    }

    private func onLine(_ line: String) {
        if let name = MessageCodec.decodeName(line) {
            first = firstPlayer()
            state = KnucklebonesRules.reset(hostName: hostName, clientName: MessageCodec.sanitizeName(name), firstPlayer: first!)
            publish()
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
        guard KnucklebonesRules.canRoll(state, player) else { return }
        state = KnucklebonesRules.beginRoll(state, player)
        publish()
        Thread.sleep(forTimeInterval: Double(rollDelayMs) / 1000.0)
        state = KnucklebonesRules.completeRoll(state, player, rollValue())
        publish()
    }

    private func placeFor(_ player: PlayerId, _ column: Int) {
        guard KnucklebonesRules.canPlace(state, player, column) else { return }
        state = KnucklebonesRules.place(state, player, column)
        publish()
    }

    public func restart() {
        guard KnucklebonesRules.canRestart(state) else { return }
        let firstPlayerNow = first ?? firstPlayer()
        first = firstPlayerNow
        state = KnucklebonesRules.reset(hostName: state.hostName, clientName: state.clientName, firstPlayer: firstPlayerNow)
        publish()
    }

    private func publish() {
        try? link.send(MessageCodec.encodeState(state))
        onState(state)
    }
}
