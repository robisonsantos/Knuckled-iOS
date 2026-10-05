import Foundation

enum BleError: Error, LocalizedError {
    case bluetoothOff
    case unauthorized
    case unsupported
    case peerLost
    case handshakeFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .bluetoothOff:
            return "Bluetooth is off. Turn it on and retry."
        case .unauthorized:
            return "Bluetooth permission was denied. Allow it in Settings, then retry."
        case .unsupported:
            return "Bluetooth LE advertising is not supported on this device."
        case .peerLost:
            return "Peer disconnected"
        case .handshakeFailed:
            return "PIN handshake failed."
        case .cancelled:
            return "Cancelled"
        }
    }
}
