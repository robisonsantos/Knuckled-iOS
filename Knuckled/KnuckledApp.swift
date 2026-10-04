import SwiftUI

@main
struct KnuckledApp: App {
    @StateObject private var session = GameSession()

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
        }
    }
}
