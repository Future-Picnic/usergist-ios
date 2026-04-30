#if os(iOS)
import UserNotifications
import Foundation

/// Notification Service Extension for Ritmus pushes.
///
/// Host apps add a new "Notification Service Extension" target in
/// Xcode and depend on the `RitmusFeedbackNSE` product. They subclass
/// this class and call `super.didReceive(...)` — that's the entire
/// integration on iOS.
///
/// What this does on every received push:
///   1. Beacons `POST /v1/sdk/push/delivered` with the payload's
///      `ritmus.deliveryId` so we record true delivered_at, distinct
///      from when the user later opens.
///   2. Optionally downloads the rich-media `imageUrl` and attaches
///      it as a `UNNotificationAttachment` so the lock-screen
///      banner shows the image.
///   3. Calls the host's `contentHandler` strictly within the 30s
///      budget the OS gives us. Implements `serviceExtensionTimeWillExpire`
///      to deliver whatever we have when we're cut off early.
///
/// Configuration is read from the host app's Info.plist:
///   • `RitmusApiUrl` — defaults to `https://api.ritmus.studio`
///   • `RitmusWriteKey` — required; same key the main SDK uses
///   • `RitmusAppGroup` — optional shared keychain access group;
///     when set, the extension reads the write key from the App Group's
///     UserDefaults instead of Info.plist (so key rotation doesn't
///     require an App Store update).
open class RitmusNotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    public override init() {
        super.init()
    }

    open override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let mutable = (request.content.mutableCopy() as? UNMutableNotificationContent)
            ?? UNMutableNotificationContent()
        self.bestAttemptContent = mutable

        let userInfo = request.content.userInfo

        // Detect silent reachability ping — never shown, but still acked
        // so the server's adaptive policy can mark the device reachable.
        if isSilentPing(userInfo) {
            ackSilent(userInfo: userInfo) { [weak self] in
                guard let self = self, let handler = self.contentHandler else { return }
                handler(UNNotificationContent())  // empty content; no banner
            }
            return
        }

        // Beacon delivered — fire-and-forget; don't block on it.
        beaconDelivered(userInfo: userInfo)

        // Rich media attachment if `ritmus.extra.imageUrl` is present.
        if let imageUrl = imageUrlFrom(userInfo: userInfo) {
            downloadAttachment(from: imageUrl) { [weak self] attachment in
                guard let self = self, let handler = self.contentHandler else { return }
                if let attachment = attachment {
                    self.bestAttemptContent?.attachments = [attachment]
                }
                handler(self.bestAttemptContent ?? mutable)
            }
            return
        }

        contentHandler(mutable)
    }

    open override func serviceExtensionTimeWillExpire() {
        // OS is about to kill us. Deliver whatever we have.
        if let handler = contentHandler, let content = bestAttemptContent {
            handler(content)
        }
    }

    // MARK: - Helpers

    private func isSilentPing(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let silent = userInfo["ritmus_silent"] as? String else { return false }
        return silent == "1"
    }

    private func imageUrlFrom(userInfo: [AnyHashable: Any]) -> URL? {
        guard
            let ritmus = userInfo["ritmus"] as? [String: Any],
            let extra = ritmus["extra"] as? [String: Any],
            let raw = extra["imageUrl"] as? String,
            let url = URL(string: raw)
        else { return nil }
        return url
    }

    private func deliveryIdFrom(userInfo: [AnyHashable: Any]) -> String? {
        guard
            let ritmus = userInfo["ritmus"] as? [String: Any],
            let id = ritmus["deliveryId"] as? String
        else { return nil }
        return id
    }

    private func pingIdFrom(userInfo: [AnyHashable: Any]) -> String? {
        return userInfo["ritmus_ping_id"] as? String
    }

    private func beaconDelivered(userInfo: [AnyHashable: Any]) {
        guard let deliveryId = deliveryIdFrom(userInfo: userInfo) else { return }
        guard let writeKey = RitmusNSEConfig.writeKey, let apiUrl = RitmusNSEConfig.apiUrl else {
            return
        }
        var req = URLRequest(url: apiUrl.appendingPathComponent("v1/sdk/push/delivered"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(writeKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "deliveryId": deliveryId,
            "occurredAt": ISO8601DateFormatter().string(from: Date()),
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let task = URLSession.shared.dataTask(with: req) { _, _, _ in }
        task.resume()
    }

    private func ackSilent(userInfo: [AnyHashable: Any], completion: @escaping () -> Void) {
        guard let pingId = pingIdFrom(userInfo: userInfo) else { return completion() }
        guard let writeKey = RitmusNSEConfig.writeKey,
              let apiUrl = RitmusNSEConfig.apiUrl,
              let anonymousId = RitmusNSEConfig.anonymousId else {
            return completion()
        }
        var req = URLRequest(url: apiUrl.appendingPathComponent("v1/sdk/push/silent-ack"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(writeKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "pingId": pingId,
            "anonymousId": anonymousId,
            "receivedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let task = URLSession.shared.dataTask(with: req) { _, _, _ in
            completion()
        }
        task.resume()
        // Safety net: don't hang forever if the network is down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { completion() }
    }

    private func downloadAttachment(
        from url: URL,
        completion: @escaping (UNNotificationAttachment?) -> Void
    ) {
        let task = URLSession.shared.downloadTask(with: url) { tempUrl, response, _ in
            guard let tempUrl = tempUrl else { return completion(nil) }
            let ext = (url.pathExtension.isEmpty ? "jpg" : url.pathExtension)
            let dst = tempUrl.deletingLastPathComponent()
                .appendingPathComponent("\(UUID().uuidString).\(ext)")
            do {
                try FileManager.default.moveItem(at: tempUrl, to: dst)
                let attachment = try UNNotificationAttachment(identifier: "ritmus-image", url: dst)
                completion(attachment)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }
}
#endif

