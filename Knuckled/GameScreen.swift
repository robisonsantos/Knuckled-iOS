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
    @State private var showLeaveConfirm = false
    @State private var resultArmed = false

    var body: some View {
        ZStack {
            FeltBackground()
            if let s = session.state {
                ScrollView {
                    VStack(spacing: 14) {
                        topBar
                        GameBoard(
                            isMine: false,
                            name: s.clientName,
                            grid: s.grid[session.peerId] ?? [[], [], []],
                            destroyed: s.destroyed.filter { $0.player == session.peerId },
                            active: s.currentTurn == session.peerId && s.status == .IN_PROGRESS,
                            canPlace: false,
                            onColumnTap: nil
                        )
                        .accessibilityIdentifier("peer-board")
                        TurnPill(state: s, myId: session.myId, peerName: s.clientName)
                        DieView(
                            value: s.lastRoll,
                            rolling: s.phase == .ROLLING,
                            enabled: session.canRoll,
                            onTap: { session.roll() }
                        )
                        if s.phase == .AWAITING_PLACEMENT && s.currentTurn == session.myId {
                            Text("Tap a column to place the die")
                                .font(.caption)
                                .foregroundStyle(AppColors.ivory)
                                .accessibilityIdentifier("place-hint")
                        }
                        GameBoard(
                            isMine: true,
                            name: s.hostName,
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
    }

    private func showResult(for s: GameState) -> Bool {
        (s.status == .FINISHED || s.status == .DRAW) && resultArmed
    }

    private var topBar: some View {
        HStack {
            Button("Leave") { showLeaveConfirm = true }
                .accessibilityIdentifier("leave")
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var leaveConfirm: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
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
