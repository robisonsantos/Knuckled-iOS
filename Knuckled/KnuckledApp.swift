import SwiftUI
import KnuckledCore

@main
struct KnuckledApp: App {
    @StateObject private var connection: ConnectionSession
    @StateObject private var settings: SettingsStore
    private let sound: AVFoundationSoundManager

    init() {
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        sound = AVFoundationSoundManager(muted: settings.muted, onMutedChanged: { settings.muted = $0 })
        // Task 14: BleConnector (default transport: fake on simulator, BLE on device)
        _connection = StateObject(wrappedValue: ConnectionSession())
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                FeltBackground()
                switch connection.state {
                case .start:
                    StartScreen()
                case .hosting(let pin):
                    HostingView(pin: pin, onCancel: { connection.cancelCurrent() })
                case .discovering:
                    DiscoverView(devices: connection.foundDevices, status: connection.statusText, onSelect: { connection.onDeviceSelected($0) }, onCancel: { connection.cancelCurrent() })
                case .enterPin(let device):
                    EnterPinView(deviceName: device.name ?? device.address, status: connection.statusText, onConfirm: { connection.onPinEntered($0) }, onCancel: { connection.cancelCurrent() })
                case .connected(let link, let peer, let isHost):
                    GameContainer(link: link, peer: peer, isHost: isHost)
                }
            }
            .environmentObject(connection)
            .environmentObject(settings)
            .environment(\.soundManager, sound)
        }
    }
}

struct GameContainer: View {
    let link: GameLink
    let peer: DeviceInfo?
    let isHost: Bool
    @EnvironmentObject var connection: ConnectionSession
    @StateObject private var session: GameSession

    init(link: GameLink, peer: DeviceInfo?, isHost: Bool) {
        self.link = link
        self.peer = peer
        self.isHost = isHost
        _session = StateObject(wrappedValue: GameSession())
    }

    var body: some View {
        GameScreen(session: session)
            .id(ObjectIdentifier(link))
            .onAppear {
                let myId: PlayerId = isHost ? .HOST : .CLIENT
                session.onPeerDisconnected = { [weak connection] in connection?.onPeerDisconnected() }
                session.connect(
                    link: link, myId: myId,
                    hostName: isHost ? connection.sanitizedName : (peer?.name ?? "Host"),
                    clientName: isHost ? "Guest" : connection.sanitizedName
                )
            }
    }
}
