import SwiftUI
import KnuckledCore

struct WinnerOverlay: View {
    let state: GameState
    let myId: PlayerId
    let onPlayAgain: () -> Void
    let onLeave: () -> Void
    @Environment(\.soundManager) private var sound

    var body: some View {
        let winner = state.winner!
        let isWinner = winner == myId
        let winnerScore = KnucklebonesRules.totalScore(state.grid[winner]!)
        let loserScore = KnucklebonesRules.totalScore(state.grid[state.opponentOf(winner)]!)
        ZStack {
            Color(red: 0x07 / 255.0, green: 0x1A / 255.0, blue: 0x10 / 255.0, opacity: 0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(isWinner ? "🏆" : "🎲").font(.system(size: 72))
                Text(isWinner ? "You win!" : "You lose!")
                    .font(AppFont.display(size: 32))
                    .foregroundStyle(.white)
                Text("\(winnerScore) – \(loserScore)")
                    .font(AppFont.display(size: 28))
                    .foregroundStyle(AppColors.gold)
                if !isWinner {
                    Text("\(state.playerName(winner)) wins!")
                        .font(.body)
                        .foregroundStyle(.white)
                }
                Button("Play again", action: onPlayAgain)
                    .buttonStyle(GoldButtonStyle())
                    .accessibilityIdentifier("play-again")
                Button("Disconnect", action: onLeave)
                    .buttonStyle(GoldSecondaryButtonStyle())
                    .accessibilityIdentifier("disconnect")
            }
            .padding(24)
            if isWinner {
                WinConfetti()
            }
        }
        .accessibilityIdentifier("winner-overlay")
        .task { sound.play(isWinner ? .win : .lose) }
    }
}

/// Lightweight win-only confetti burst (~50 gold/ivory/red rectangles
/// falling with animation). Static when Reduce Motion is on.
private struct WinConfetti: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var falling = false
    private let pieces: [ConfettiPiece] = (0..<50).map { _ in ConfettiPiece.random() }

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                Rectangle()
                    .fill(piece.color)
                    .frame(width: piece.w, height: piece.h)
                    .offset(x: piece.x, y: reduceMotion ? piece.staticY : (falling ? piece.endY : piece.startY))
                    .rotationEffect(.degrees(reduceMotion ? piece.rotation : (falling ? piece.rotation + 360 : piece.rotation)))
                    .opacity(reduceMotion ? 0.9 : (falling ? 0.0 : 1.0))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.5)) { falling = true }
        }
    }
}

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let staticY: CGFloat
    let color: Color
    let w: CGFloat
    let h: CGFloat
    let rotation: Double

    static func random() -> ConfettiPiece {
        let colors: [Color] = [AppColors.gold, AppColors.ivory, AppColors.error]
        return ConfettiPiece(
            x: CGFloat.random(in: -160...160),
            startY: CGFloat.random(in: -340...(-240)),
            endY: CGFloat.random(in: 240...420),
            staticY: CGFloat.random(in: -260...(-120)),
            color: colors.randomElement()!,
            w: CGFloat.random(in: 6...10),
            h: CGFloat.random(in: 8...14),
            rotation: Double.random(in: 0...360)
        )
    }
}

struct DrawOverlay: View {
    let state: GameState
    let myId: PlayerId
    let onPlayAgain: () -> Void
    let onLeave: () -> Void

    var body: some View {
        let myScore = KnucklebonesRules.totalScore(state.grid[myId]!)
        let peerScore = KnucklebonesRules.totalScore(state.grid[state.opponentOf(myId)]!)
        ZStack {
            Color(red: 0x07 / 255.0, green: 0x1A / 255.0, blue: 0x10 / 255.0, opacity: 0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("🎲").font(.system(size: 72))
                Text("Draw")
                    .font(AppFont.display(size: 32))
                    .foregroundStyle(.white)
                Text("\(myScore) – \(peerScore)")
                    .font(AppFont.display(size: 28))
                    .foregroundStyle(AppColors.gold)
                Button("Play again", action: onPlayAgain)
                    .buttonStyle(GoldButtonStyle())
                    .accessibilityIdentifier("play-again")
                Button("Disconnect", action: onLeave)
                    .buttonStyle(GoldSecondaryButtonStyle())
                    .accessibilityIdentifier("disconnect")
            }
            .padding(24)
        }
        .accessibilityIdentifier("draw-overlay")
    }
}
