import Foundation
import CoreBluetooth

/// Frozen GATT layout (spec table — do NOT change after first release).
enum BleUUIDs {
    static let service = CBUUID(string: "8B6B4A85-57B3-4BE8-ACDE-BE209FBAAE7A")
    static let write = CBUUID(string: "AAF90241-0F50-42CF-ADFC-2BAADE92ACD1")
    static let notify = CBUUID(string: "3FE6B62B-8DF0-4B4D-BB7E-8048B74461AA")
    static let localName = "Knuckled"
    static let clientCharacteristicConfig = CBUUID(string: "00002902-0000-1000-8000-00805f9b34fb")
}
