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
                Button("Disconnect", action: onLeave)
                    .buttonStyle(GoldSecondaryButtonStyle())
            }
            .padding(24)
        }
        .accessibilityIdentifier("winner-overlay")
        .task { sound.play(isWinner ? .win : .lose) }
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
                Button("Disconnect", action: onLeave)
                    .buttonStyle(GoldSecondaryButtonStyle())
            }
            .padding(24)
        }
        .accessibilityIdentifier("draw-overlay")
    }
}
