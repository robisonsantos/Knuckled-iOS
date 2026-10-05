import SwiftUI

@main
struct KnuckledApp: App {
    @StateObject private var session = GameSession()
    @StateObject private var settings: SettingsStore
    private let sound: AVFoundationSoundManager

    init() {
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        sound = AVFoundationSoundManager(muted: settings.muted, onMutedChanged: { settings.muted = $0 })
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                FeltBackground()
                if session.inGame {
                    GameScreen(session: session)
                } else {
                    StartScreen(session: session)
                }
            }
            .environmentObject(settings)
            .environment(\.soundManager, sound)
        }
    }
}
