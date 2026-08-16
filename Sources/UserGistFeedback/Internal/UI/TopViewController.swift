import Foundation
import UIKit

enum TopViewControllerLocator {
    /// Returns the top-most view controller in the foreground key window,
    /// or `nil` if no scene is currently presentable. Used by every
    /// SDK-presented modal (prompts, surveys, requests).
    static func topMost() -> UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene,
                  scene.activationState == .foregroundActive else { continue }
            for window in ws.windows where window.isKeyWindow {
                var cur = window.rootViewController
                while let presented = cur?.presentedViewController {
                    cur = presented
                }
                return cur
            }
        }
        return nil
    }
}
