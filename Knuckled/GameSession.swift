import Foundation
import Combine
import KnuckledCore

/// Owns one game session over any GameLink (solo loopback, fake, or BLE).
/// HOST runs a GameHost; CLIENT sends NAME and renders STATE broadcasts.
/// All @Published updates happen on the main thread.
final class GameSession: ObservableObject {
    @Published private(set) var state: GameState?
    @Published private(set) var playerName: String = "Player"
    @Published private(set) var peerDisconnected = false

    var onPeerDisconnected: () -> Void = {}

    private(set) var myId: PlayerId = .HOST
    private(set) var peerId: PlayerId = .CLIENT

    private var host: GameHost?
    private var link: GameLink?
    private var cpuLink: GameLink?

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

    /// Solo convenience: loopback pair + CPU client, then the host path.
    /// Production defaults mirror Android (2s roll, human pacing).
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
        connect(
            link: humanLink, myId: .HOST,
            hostName: clean.isEmpty ? "Player" : clean, clientName: CpuPlayer.name,
            rollValue: rollValue, rollDelayMs: rollDelayMs, firstPlayer: firstPlayer
        )
        self.cpuLink = cpuLink
        playerName = clean.isEmpty ? "Player" : clean
    }

    /// PvP path: attach to an already-connected link in either role.
    func connect(
        link: GameLink,
        myId: PlayerId,
        hostName: String,
        clientName: String,
        rollValue: @escaping () -> Int = { Int.random(in: 1...6) },
        rollDelayMs: Int = 2000,
        firstPlayer: @escaping () -> PlayerId = { Bool.random() ? .HOST : .CLIENT }
    ) {
        disconnect()
        self.link = link
        self.myId = myId
        self.peerId = myId == .HOST ? .CLIENT : .HOST
        self.playerName = myId == .HOST ? hostName : clientName
        self.peerDisconnected = false
        if myId == .HOST {
            let host = GameHost(
                link: link,
                hostName: hostName,
                rollValue: rollValue,
                rollDelayMs: rollDelayMs,
                firstPlayer: firstPlayer,
                onState: { [weak self] s in
                    DispatchQueue.main.async { self?.state = s }
                }
            )
            self.host = host
            link.onClosed = { [weak self] in self?.handlePeerClosed() }
            host.connect()
        } else {
            link.onLine = { [weak self] line in
                guard let self, let s = MessageCodec.decodeState(line) else { return }
                let captured = s
                DispatchQueue.main.async { self.state = captured }
            }
            link.onClosed = { [weak self] in self?.handlePeerClosed() }
            try? link.send(MessageCodec.encodeName(clientName))
        }
    }

    /// Async: the host roll blocks ~rollDelayMs mid-roll (same as Android's IO dispatcher).
    /// As client this sends ROLL (host rolls for us).
    func roll() {
        if myId == .HOST {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.host?.hostRoll()
            }
        } else {
            try? link?.send(MessageCodec.encodeRoll())
        }
    }

    func place(_ column: Int) {
        if myId == .HOST {
            host?.hostPlace(column)
        } else {
            try? link?.send(MessageCodec.encodePlace(column))
        }
    }

    func playAgain() {
        if myId == .HOST {
            host?.restart()
        } else {
            try? link?.send(MessageCodec.encodeRestart())
        }
    }

    func disconnect() {
        link?.close()
        link = nil
        cpuLink = nil
        host = nil
        state = nil
    }

    private func handlePeerClosed() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.peerDisconnected = true
            self.onPeerDisconnected()
        }
    }
}
