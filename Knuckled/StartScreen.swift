import SwiftUI
import KnuckledCore

struct StartScreen: View {
    @EnvironmentObject private var connection: ConnectionSession
    @EnvironmentObject private var settings: SettingsStore
    @State private var showPvP = false

    /// "0.9.1 (1)" from the bundle; semver lives in MARKETING_VERSION.
    static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        ZStack {
            FeltBackground()
            if showPvP {
                PvPView(onBack: { showPvP = false })
            } else {
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
                                    .foregroundStyle(AppColors.ivory)
                                Spacer()
                                Button(action: { settings.onboardingSeen = true }) {
                                    Image(systemName: "xmark")
                                        .foregroundStyle(AppColors.ivory)
                                }
                                .accessibilityIdentifier("hint-dismiss")
                            }
                            .padding(12)
                        }
                        .accessibilityIdentifier("hint-card")
                    }
                    NameField(text: $connection.playerName)
                    Button("Play vs CPU") {
                        connection.startSinglePlayer()
                    }
                    .buttonStyle(GoldButtonStyle())
                    .accessibilityIdentifier("single-player-button")
                    Button("Player vs Player") { showPvP = true }
                        .buttonStyle(GoldSecondaryButtonStyle())
                        .accessibilityIdentifier("pvp-button")
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
                    Text("v\(StartScreen.appVersion)")
                        .font(.caption2)
                        .foregroundStyle(AppColors.ivory)
                        .opacity(0.6)
                        .accessibilityIdentifier("app-version")
                }
                .padding(24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }
}

/// Dedicated full-screen PvP menu (same felt background). Host/Join reuse
/// `ConnectionSession` unchanged; Back returns to the main menu.
private struct PvPView: View {
    @EnvironmentObject private var connection: ConnectionSession
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Player vs Player")
                    .font(AppFont.display(size: 24))
                    .foregroundStyle(AppColors.gold)
                    .accessibilityIdentifier("pvp-title")
                NameField(text: $connection.playerName)
                Button("Host a game") { connection.onHostClicked() }
                    .buttonStyle(GoldButtonStyle())
                    .accessibilityIdentifier("host-button")
                Button("Join a game") { connection.onDiscoverClicked() }
                    .buttonStyle(GoldSecondaryButtonStyle())
                    .accessibilityIdentifier("join-button")
                #if DEBUG
                Picker("Transport", selection: $connection.useFake) {
                    Text("Nearby").tag(false)
                    Text("Fake").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("transport-picker")
                #endif
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
                Button("Back") { onBack() }
                    .buttonStyle(GoldSecondaryButtonStyle())
                    .accessibilityIdentifier("pvp-back")
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Android-parity gold outlined name field: transparent background, gold
/// rounded-rectangle border, small gold caption, ivory text, gold cursor.
private struct NameField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your name")
                .font(.caption)
                .foregroundStyle(AppColors.gold)
            TextField("Your name", text: $text)
                .foregroundStyle(AppColors.ivory)
                .tint(AppColors.gold)
                .accentColor(AppColors.gold)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(focused ? AppColors.gold : AppColors.glassBorderGold, lineWidth: 1)
                )
                .focused($focused)
                .accessibilityIdentifier("name-field")
        }
    }
}
