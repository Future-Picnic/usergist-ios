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
                guard !window.isHidden, window.alpha > 0,
                      let root = window.rootViewController else { continue }
                return presentableController(from: root)
            }
        }
        return nil
    }

    /// A settled presented navigation controller may be the host's main UI.
    /// Startup readiness comes from the host gate; UIKit checks only establish
    /// whether presentation is safe right now, not whether loading is finished.
    static func presentableController(from root: UIViewController) -> UIViewController? {
        var current = root
        while true {
            guard !current.isBeingPresented, !current.isBeingDismissed,
                  current.transitionCoordinator == nil else { return nil }
            if let presented = current.presentedViewController {
                guard !(presented is UIAlertController) else { return nil }
                current = presented
            } else if let navigation = current as? UINavigationController,
               let visible = navigation.visibleViewController {
                current = visible
            } else if let tabs = current as? UITabBarController,
                      let selected = tabs.selectedViewController {
                current = selected
            } else {
                // Full-screen host navigation legitimately detaches the old
                // root's view. Require visibility on the final presenter only.
                return current.viewIfLoaded?.window != nil ? current : nil
            }
        }
    }
}
