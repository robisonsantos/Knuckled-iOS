import UIKit

/// Turn haptics (Android parity: 150ms one-shot vibration on your turn).
enum Haptics {
    static func turn() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
}
