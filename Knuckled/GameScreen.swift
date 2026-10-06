import SwiftUI
import KnuckledCore

struct TurnPill: View {
    let state: GameState
    let myId: PlayerId
    let peerName: String

    var body: some View {
        Group {
            if state.status == .IN_PROGRESS {
                Text(state.phase == .ROLLING ? "Rolling…" : state.currentTurn == myId ? "Your turn" : "\(peerName)'s turn")
                    .foregroundStyle(AppColors.ivory)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppColors.glassWhite)
                    .overlay(Capsule().stroke(AppColors.glassBorderGold, lineWidth: 1))
                    .clipShape(Capsule())
                    .accessibilityIdentifier("turn-pill")
            }
        }
    }
}

struct GameScreen: View {
    @ObservedObject var session: GameSession
    @Environment(\.soundManager) private var sound
    @EnvironmentObject private var settings: SettingsStore
    @State private var showLeaveConfirm = false
    @State private var resultArmed = false

    var body: some View {
        ZStack {
            FeltBackground()
            if let s = session.state {
                // Role-aware names (Android parity: playerName(myId/peerId)).
                // Hardcoding hostName/clientName swaps the boards for joiners.
                let myName = session.myId == .HOST ? s.hostName : s.clientName
                let peerName = session.myId == .HOST ? s.clientName : s.hostName
                ScrollView {
                    VStack(spacing: 14) {
                        topBar
                        if session.peerDisconnected {
                            GlassCard {
                                Text("Peer disconnected")
                                    .foregroundStyle(AppColors.ivory)
                                    .padding(12)
                            }
                            .accessibilityIdentifier("peer-banner")
                        }
                        GameBoard(
                            isMine: false,
                            name: peerName,
                            grid: s.grid[session.peerId] ?? [[], [], []],
                            destroyed: s.destroyed.filter { $0.player == session.peerId },
                            active: s.currentTurn == session.peerId && s.status == .IN_PROGRESS,
                            canPlace: false,
                            onColumnTap: nil
                        )
                        .accessibilityIdentifier("peer-board")
                        TurnPill(state: s, myId: session.myId, peerName: peerName)
                        DiceSceneView(
                            value: s.lastRoll,
                            rolling: s.phase == .ROLLING,
                            enabled: session.canRoll,
                            onTap: { sound.play(.tap); session.roll() }
                        )
                        if s.phase == .AWAITING_PLACEMENT && s.currentTurn == session.myId {
                            Text("Tap a column to place the die")
                                .font(.caption)
                                .foregroundStyle(AppColors.ivory)
                                .accessibilityIdentifier("place-hint")
                        }
                        GameBoard(
                            isMine: true,
                            name: myName,
                            grid: s.grid[session.myId] ?? [[], [], []],
                            destroyed: s.destroyed.filter { $0.player == session.myId },
                            active: s.currentTurn == session.myId && s.status == .IN_PROGRESS,
                            canPlace: s.phase == .AWAITING_PLACEMENT && s.currentTurn == session.myId,
                            onColumnTap: { session.place($0) }
                        )
                        .accessibilityIdentifier("own-board")
                    }
                    .padding(16)
                }
                if showResult(for: s) {
                    if s.status == .FINISHED {
                        WinnerOverlay(state: s, myId: session.myId, onPlayAgain: { session.playAgain() }, onLeave: leave)
                    } else {
                        DrawOverlay(state: s, myId: session.myId, onPlayAgain: { session.playAgain() }, onLeave: leave)
                    }
                }
            } else {
                Text("Waiting for state…").foregroundStyle(AppColors.ivory)
            }
            if showLeaveConfirm {
                leaveConfirm
                    .accessibilityIdentifier("leave-confirm")
            }
        }
        .task(id: session.state?.status) {
            // Re-arms on every status change; shows the overlay 1200ms after terminal.
            resultArmed = false
            let status = session.state?.status
            if status == .FINISHED || status == .DRAW {
                try? await Task.sleep(for: .milliseconds(1200))
                if session.state?.status == status { resultArmed = true }
            }
        }
        .task(id: session.state?.phase) {
            guard session.state?.phase == .ROLLING else {
                sound.stopLoop()
                if session.state?.phase == .AWAITING_PLACEMENT { sound.play(.land) }
                return
            }
            sound.startLoop(.rattle)
        }
        .task(id: session.state) {
            guard settings.autoRoll,
                  let s = session.state,
                  s.status == .IN_PROGRESS, s.phase == .IDLE, s.currentTurn == session.myId,
                  s.grid.values.contains(where: { $0.contains(where: { !$0.isEmpty }) })
            else { return }
            session.roll()
        }
        .onChange(of: session.state?.currentTurn) { _, newTurn in
            if session.state?.status == .IN_PROGRESS, newTurn == session.myId {
                Haptics.turn()
            }
        }
    }

    private func showResult(for s: GameState) -> Bool {
        (s.status == .FINISHED || s.status == .DRAW) && resultArmed
    }

    private var topBar: some View {
        HStack {
            Button("Leave") { showLeaveConfirm = true }
                .accessibilityIdentifier("leave")
            Spacer()
            Button(action: { settings.autoRoll.toggle() }) {
                Image(systemName: "dice")
                    .foregroundStyle(settings.autoRoll ? AppColors.gold : Color(red: 0xF3 / 255.0, green: 0xE7 / 255.0, blue: 0xC3 / 255.0, opacity: 0.5))
            }
            .accessibilityIdentifier("auto-roll")
            .accessibilityLabel(settings.autoRoll ? "Auto-roll on" : "Auto-roll off")
            Button(action: {
                sound.setMuted(!sound.isMuted)
                settings.muted = sound.isMuted
            }) {
                Image(systemName: sound.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(AppColors.gold)
            }
            .accessibilityIdentifier("mute")
        }
        .padding(.horizontal, 8)
    }

    private var leaveConfirm: some View {
        ZStack {
            Color(red: 0, green: 0, blue: 0, opacity: 0.5).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Leave game?").font(.headline).foregroundStyle(AppColors.ivory)
                Text("Are you sure? Your progress will be lost.").font(.body).foregroundStyle(AppColors.ivory)
                HStack(spacing: 12) {
                    Button("Stay") { showLeaveConfirm = false }
                        .buttonStyle(GoldSecondaryButtonStyle())
                        .accessibilityIdentifier("stay")
                    Button("Leave") { leave() }
                        .buttonStyle(GoldButtonStyle())
                        .accessibilityIdentifier("confirm-leave")
                }
            }
            .padding(24)
            .background(AppColors.feltMid)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(32)
        }
    }

    private func leave() {
        showLeaveConfirm = false
        session.disconnect()
    }
}
