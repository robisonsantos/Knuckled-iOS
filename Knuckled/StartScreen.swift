import SwiftUI
import KnuckledCore

struct StartScreen: View {
    @EnvironmentObject private var connection: ConnectionSession
    @EnvironmentObject private var settings: SettingsStore

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
                TextField("Your name", text: $connection.playerName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("name-field")
                Button("Play vs CPU") {
                    connection.startSinglePlayer()
                }
                .buttonStyle(GoldButtonStyle())
                .accessibilityIdentifier("single-player-button")
                Button("Host a game") { connection.onHostClicked() }
                    .buttonStyle(GoldButtonStyle())
                    .accessibilityIdentifier("host-button")
                Button("Join a game") { connection.onDiscoverClicked() }
                    .buttonStyle(GoldSecondaryButtonStyle())
                    .accessibilityIdentifier("join-button")
                Picker("Transport", selection: $connection.useFake) {
                    Text("Nearby").tag(false)
                    Text("Fake").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("transport-picker")
                if let error = connection.errorText {
                    GlassCard {
                        HStack {
                            Text(error)
                                .foregroundStyle(AppColors.error)
                                .accessibilityIdentifier("connection-error")
                            Spacer()
                            Button("Dismiss") { connection.dismissError() }
                                .accessibilityIdentifier("error-dismiss")
                        }
                        .padding(12)
                    }
                }
            }
            .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
