import Foundation
import Combine
import KnuckledCore

enum ConnectionState {
    case start
    case hosting(pin: String)
    case discovering
    case enterPin(device: DeviceInfo)
    case connected(link: GameLink, peer: DeviceInfo?, isHost: Bool)
}

/// Connection flow state machine (Android parity: ConnectionViewModel route
/// states, background-thread blocking calls, main-thread publishing).
/// Transport note: Android exposes an RFCOMM/BLE toggle; iOS is BLE-only
/// (plus the fake). Labels differ by platform by design — not renamed.
final class ConnectionSession: ObservableObject {
    @Published private(set) var state: ConnectionState = .start
    @Published var playerName = ""
    @Published private(set) var statusText = ""
    @Published private(set) var foundDevices: [DeviceInfo] = []
    @Published private(set) var errorText: String?
    #if DEBUG
    #if targetEnvironment(simulator)
    @Published var useFake = true
    #else
    @Published var useFake = false
    #endif
    #else
    @Published var useFake = false
    #endif

    var isStart: Bool { if case .start = state { return true }; return false }
    var isConnected: Bool { if case .connected = state { return true }; return false }
    var hostPin: String { if case .hosting(let pin) = state { return pin }; return "" }

    private let fake = FakeConnector()
    private let ble = BleConnector()
    /// Injected connector (tests / previews). When set, it is the active
    /// transport for the whole session — discover+connect share the one
    /// instance, and cancelCurrent()/disconnect() reach it via cancel().
    private var injected: BluetoothConnector?
    private var active: BluetoothConnector {
        #if DEBUG
        injected ?? (useFake ? fake : ble)
        #else
        injected ?? ble
        #endif
    }
    private var selectedDevice: DeviceInfo?
    private var currentLink: GameLink?
    private var retainedLinks: [GameLink] = []
    private(set) var sanitizedName = ""
    private(set) var isHost = true

    init(connector: BluetoothConnector? = nil) {
        // Injected transport for tests/previews; nil selects via useFake.
        self.injected = connector
        #if !DEBUG
        useFake = false
        #endif
    }

    func startSinglePlayer() {
        let clean = MessageCodec.sanitizeName(playerName)
        guard !clean.isEmpty else { showError("Enter your name"); return }
        sanitizedName = clean
        isHost = true
        let (humanLink, cpuLink) = InMemoryLinkPair.make()
        runCpuClient(cpuLink)
        retainedLinks.append(cpuLink)
        onConnected(link: humanLink, peer: nil, isHost: true)
    }

    func onHostClicked() {
        let clean = MessageCodec.sanitizeName(playerName)
        guard !clean.isEmpty else { showError("Enter your name"); return }
        sanitizedName = clean
        isHost = true
        // Fake transport requires the fixed PIN 1234 (FakeConnector
        // rejects anything else; UI tests join with 1234). Real BLE
        // hosts get a random 4-digit PIN.
        let pin: String
        if active is FakeConnector {
            pin = FakeConnector.pin
        } else {
            pin = PinGenerator.generate()
        }
        state = .hosting(pin: pin)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let link = try self.active.listen(pin: pin)
                DispatchQueue.main.async { self.onConnected(link: link, peer: nil, isHost: true) }
            } catch {
                DispatchQueue.main.async {
                    // A user cancel is silent: cancelCurrent() already reset
                    // to Start; anything else surfaces as an error.
                    if self.isCancel(error) {
                        self.state = .start
                    } else {
                        self.showError(error.localizedDescription)
                        self.state = .start
                    }
                }
            }
        }
    }

    func onDiscoverClicked() {
        let clean = MessageCodec.sanitizeName(playerName)
        guard !clean.isEmpty else { showError("Enter your name"); return }
        sanitizedName = clean
        isHost = false
        foundDevices = []
        state = .discovering
        statusText = "Searching for devices..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let devices = try self.active.discover()
                DispatchQueue.main.async {
                    self.foundDevices = devices
                    self.statusText = devices.isEmpty ? "No devices found — tap Host first" : ""
                }
            } catch {
                DispatchQueue.main.async {
                    self.showError(error.localizedDescription)
                    self.state = .start
                }
            }
        }
    }

    func onDeviceSelected(_ device: DeviceInfo) {
        selectedDevice = device
        statusText = ""
        errorText = nil
        state = .enterPin(device: device)
    }

    func onPinEntered(_ pin: String) {
        guard let device = selectedDevice else { return }
        statusText = "Connecting..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let link = try self.active.connect(device: device, pin: pin)
                DispatchQueue.main.async { self.onConnected(link: link, peer: device, isHost: false) }
            } catch {
                let message = String(describing: error)
                let lower = message.lowercased()
                let friendly = (lower.contains("pin") || lower.contains("handshake"))
                    ? "Wrong code. Try again." : message
                DispatchQueue.main.async {
                    // Android parity: ConnectionViewModel.resetForError()
                    // returns to Start on connect failure (including wrong
                    // PIN) with the error banner — iOS stays aligned.
                    if self.isCancel(error) {
                        self.state = .start
                    } else {
                        self.showError(friendly)
                        self.state = .start
                    }
                }
            }
        }
    }

    /// True for user-cancel errors (silent reset, no error banner).
    private func isCancel(_ error: Error) -> Bool {
        (error as? BleError) == .cancelled || (error as? FakeConnectorError) == .cancelled
    }

    func cancelCurrent() {
        active.cancel()
        currentLink?.close()
        retainedLinks = []
        statusText = ""
        foundDevices = []
        selectedDevice = nil
        state = .start
    }

    func disconnect() {
        active.cancel()
        currentLink?.close()
        currentLink = nil
        retainedLinks = []
        statusText = "Disconnected"
        foundDevices = []
        selectedDevice = nil
        state = .start
    }

    func onPeerDisconnected() {
        active.cancel()
        currentLink?.close()
        currentLink = nil
        retainedLinks = []
        statusText = "Peer disconnected"
        foundDevices = []
        selectedDevice = nil
        state = .start
    }

    func dismissError() { errorText = nil }

    private func showError(_ message: String) { errorText = message }

    private func onConnected(link: GameLink, peer: DeviceInfo?, isHost: Bool) {
        currentLink?.close()
        currentLink = link
        self.isHost = isHost
        statusText = ""
        errorText = nil
        state = .connected(link: link, peer: peer, isHost: isHost)
    }
}
