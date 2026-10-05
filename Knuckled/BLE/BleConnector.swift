import Foundation
import KnuckledCore

/// Real radio transport behind the same blocking facade as the fake.
/// Fresh peripheral/central per call (mirrors Android connector usage).
final class BleConnector: BluetoothConnector {
    func listen(pin: String) throws -> GameLink {
        try BlePeripheralHost().listen(pin: pin)
    }

    func connect(device: DeviceInfo, pin: String) throws -> GameLink {
        try BleCentralClient().connect(device: device, pin: pin)
    }

    func discover() throws -> [DeviceInfo] {
        try BleCentralClient().discover()
    }
}
