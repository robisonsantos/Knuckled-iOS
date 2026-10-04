import SwiftUI
import KnuckledCore

struct StartScreen: View {
    @ObservedObject var session: GameSession
    @State private var name: String = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            FeltBackground()
            VStack(spacing: 16) {
                Text("⚂")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.dieIvoryLight)
                Text("Knuckled")
                    .font(AppFont.display(size: 32))
                    .foregroundStyle(AppColors.gold)
                    .accessibilityIdentifier("start-title")
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("name-field")
                if let error {
                    Text(error).foregroundStyle(AppColors.error)
                }
                Button("Play vs CPU") {
                    if MessageCodec.sanitizeName(name).isEmpty {
                        error = "Enter your name"
                    } else {
                        session.startSinglePlayer(name: name)
                    }
                }
                .buttonStyle(GoldButtonStyle())
                .accessibilityIdentifier("single-player-button")
            }
            .padding(24)
        }
    }
}
