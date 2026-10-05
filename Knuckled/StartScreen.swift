import SwiftUI
import KnuckledCore

struct StartScreen: View {
    @ObservedObject var session: GameSession
    @EnvironmentObject private var settings: SettingsStore
    @State private var name: String = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            FeltBackground()
            ScrollView {
            VStack(spacing: 16) {
                Text("⚂")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.dieIvoryLight)
                Text("Knuckled")
                    .font(AppFont.display(size: 32))
                    .foregroundStyle(AppColors.gold)
                    .accessibilityIdentifier("start-title")
                if !settings.onboardingSeen {
                    GlassCard {
                        HStack {
                            Text("Host on one phone, join from the other — when a 3x3 grid fills up, the highest score wins.")
                                .font(.caption)
                            Spacer()
                            Button(action: { settings.onboardingSeen = true }) {
                                Image(systemName: "xmark")
                            }
                            .accessibilityIdentifier("hint-dismiss")
                        }
                        .padding(12)
                    }
                    .accessibilityIdentifier("hint-card")
                }
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("name-field")
                if let error {
                    Text(error).foregroundStyle(AppColors.error)
                        .accessibilityIdentifier("name-error")
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
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
