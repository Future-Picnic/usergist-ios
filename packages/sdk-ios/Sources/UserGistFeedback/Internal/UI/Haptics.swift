import Foundation
import UIKit

/// Thin wrapper over `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`.
enum Haptics {
    static func impactLight() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare()
        gen.impactOccurred()
    }

    static func success() {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
    }
}
