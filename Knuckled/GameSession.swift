import Foundation
import Combine
import KnuckledCore

/// Owns one solo session: GameHost (us, HOST) + CPU client over an in-memory link.
/// All @Published updates happen on the main thread.
final class GameSession: ObservableObject {
    @Published private(set) var state: GameState?
    @Published private(set) var playerName: String = "Player"

    let myId: PlayerId = .HOST
    let peerId: PlayerId = .CLIENT

    private var host: GameHost?
    private var link: GameLink?

    var inGame: Bool { state != nil }

    var isMyTurn: Bool {
        guard let s = state else { return false }
        return s.status == .IN_PROGRESS && s.currentTurn == myId
    }

    var canRoll: Bool {
        guard let s = state else { return false }
        return KnucklebonesRules.canRoll(s, myId)
    }

    func canPlace(_ column: Int) -> Bool {
        guard let s = state else { return false }
        return KnucklebonesRules.canPlace(s, myId, column)
    }

    func startSinglePlayer(
        name: String,
        rollDelayMs: Int = 2000,
        rollValue: @escaping () -> Int = { Int.random(in: 1...6) },
        firstPlayer: @escaping () -> PlayerId = { Bool.random() ? .HOST : .CLIENT },
        preRollDelayMs: Double = CpuPacing.preRollSeconds,
        thinkDelay: @escaping () -> Double = CpuPacing.naturalThink
    ) {
        disconnect()
        let clean = MessageCodec.sanitizeName(name)
        let (humanLink, cpuLink) = InMemoryLinkPair.make()
        runCpuClient(cpuLink, preRollDelayMs: preRollDelayMs, thinkDelay: thinkDelay)
        let h = GameHost(
            link: humanLink,
            hostName: clean.isEmpty ? "Player" : clean,
            rollValue: rollValue,
            rollDelayMs: rollDelayMs,
            firstPlayer: firstPlayer,
            onState: { [weak self] s in
                DispatchQueue.main.async { self?.state = s }
            }
        )
        self.link = humanLink
        self.host = h
        self.playerName = clean.isEmpty ? "Player" : clean
        h.connect()
    }

    /// Async: the host roll blocks ~rollDelayMs mid-roll (same as Android's IO dispatcher).
    func roll() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.host?.hostRoll()
        }
    }

    func place(_ column: Int) {
        host?.hostPlace(column)
    }

    func playAgain() {
        host?.restart()
    }

    func disconnect() {
        link?.close()
        link = nil
        host = nil
        state = nil
    }
}
