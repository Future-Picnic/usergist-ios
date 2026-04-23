import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Permission status returned by `getPushPermissionStatus` and
/// `requestPushPermission`.
public enum PushPermissionStatus: String, Codable, Sendable {
    case notDetermined
    case denied
    case granted
    case provisional
    case ephemeral
}

/// Payload for a received/opened push, parsed from the APNs payload.
public struct RitmusPushMessage: Sendable {
    public let campaignId: String?
    public let variantId: String?
    public let deliveryId: String?
    public let language: String?
    public let deepLink: String?
    public let title: String?
    public let body: String?

    public init(
        campaignId: String? = nil,
        variantId: String? = nil,
        deliveryId: String? = nil,
        language: String? = nil,
        deepLink: String? = nil,
        title: String? = nil,
        body: String? = nil
    ) {
        self.campaignId = campaignId
        self.variantId = variantId
        self.deliveryId = deliveryId
        self.language = language
        self.deepLink = deepLink
        self.title = title
        self.body = body
    }

    /// Attempts to parse a Ritmus push message out of an APNs userInfo
    /// dictionary. Returns `nil` if the payload doesn't contain the Ritmus
    /// envelope.
    public static func parse(userInfo: [AnyHashable: Any]) -> RitmusPushMessage? {
        guard let ritmus = userInfo["ritmus"] as? [String: Any] else { return nil }
        let aps = userInfo["aps"] as? [String: Any]
        let alert = aps?["alert"] as? [String: Any]
        return RitmusPushMessage(
            campaignId: ritmus["campaignId"] as? String,
            variantId: ritmus["variantId"] as? String,
            deliveryId: ritmus["deliveryId"] as? String,
            language: ritmus["language"] as? String,
            deepLink: ritmus["deepLink"] as? String,
            title: alert?["title"] as? String,
            body: alert?["body"] as? String
        )
    }
}

/// Callback surface for received / opened / action-tapped pushes.
public struct PushHandlers: Sendable {
    public var onReceive: (@Sendable (RitmusPushMessage, [AnyHashable: Any]) -> Void)?
    public var onOpen: (@Sendable (RitmusPushMessage) -> Void)?
    public var onAction: (@Sendable (RitmusPushMessage, String) -> Void)?

    public init(
        onReceive: (@Sendable (RitmusPushMessage, [AnyHashable: Any]) -> Void)? = nil,
        onOpen: (@Sendable (RitmusPushMessage) -> Void)? = nil,
        onAction: (@Sendable (RitmusPushMessage, String) -> Void)? = nil
    ) {
        self.onReceive = onReceive
        self.onOpen = onOpen
        self.onAction = onAction
    }
}

/// Public push-notifications surface.
///
/// ## Integration
///
/// The SDK does not take over `UNUserNotificationCenterDelegate` — host apps
/// usually already set one. Host apps should forward lifecycle events to the
/// SDK manually:
///
/// ```swift
/// // In AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
/// Ritmus.shared.push.didReceiveDeviceToken(deviceToken)
///
/// // In UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:...)
/// Ritmus.shared.push.handleReceived(userInfo: notification.request.content.userInfo)
///
/// // In UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)
/// Ritmus.shared.push.handleOpened(userInfo: response.notification.request.content.userInfo,
///                                  actionIdentifier: response.actionIdentifier)
/// ```
public final class RitmusPush {
    private let registerTokenFn: (String) -> Void
    private let trackFn: (String, [String: Any]?) -> Void
    private let lock = NSLock()
    private var handlers: PushHandlers = PushHandlers()
    private var cachedToken: String?

    init(
        registerToken: @escaping (String) -> Void,
        track: @escaping (String, [String: Any]?) -> Void
    ) {
        self.registerTokenFn = registerToken
        self.trackFn = track
    }

    // MARK: - Public API

    /// Presents the OS push-permission prompt. On iOS this wraps
    /// `UNUserNotificationCenter.requestAuthorization`. Safe to call multiple
    /// times — the second call is a no-op if permission already decided.
    public func requestPermission(
        options: UNAuthorizationOptions = [.alert, .badge, .sound],
        completion: ((PushPermissionStatus) -> Void)? = nil
    ) {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, _ in
            let status: PushPermissionStatus = granted ? .granted : .denied
            DispatchQueue.main.async {
                if granted {
                    #if canImport(UIKit)
                    UIApplication.shared.registerForRemoteNotifications()
                    #endif
                }
                completion?(status)
            }
        }
        #else
        completion?(.denied)
        #endif
    }

    /// Synchronous read of current permission status.
    public func getPermissionStatus(completion: @escaping (PushPermissionStatus) -> Void) {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: PushPermissionStatus = {
                switch settings.authorizationStatus {
                case .notDetermined: return .notDetermined
                case .denied: return .denied
                case .authorized: return .granted
                case .provisional: return .provisional
                case .ephemeral: return .ephemeral
                @unknown default: return .notDetermined
                }
            }()
            completion(status)
        }
        #else
        completion(.denied)
        #endif
    }

    /// Sets foreground-receive / open / action callbacks. Replaces any
    /// previously-registered handlers.
    public func setHandlers(_ handlers: PushHandlers) {
        lock.lock()
        self.handlers = handlers
        lock.unlock()
    }

    /// Called by the host app after
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` fires.
    public func didReceiveDeviceToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        lock.lock()
        cachedToken = hex
        lock.unlock()
        registerTokenFn(hex)
    }

    /// Call from `UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:...)`.
    public func handleReceived(userInfo: [AnyHashable: Any]) {
        guard let msg = RitmusPushMessage.parse(userInfo: userInfo) else { return }
        emit(event: "$push_received", message: msg)
        lock.lock()
        let cb = handlers.onReceive
        lock.unlock()
        cb?(msg, userInfo)
    }

    /// Call from `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)`.
    public func handleOpened(userInfo: [AnyHashable: Any], actionIdentifier: String? = nil) {
        guard let msg = RitmusPushMessage.parse(userInfo: userInfo) else { return }
        if let actionIdentifier, actionIdentifier != UNNotificationDefaultActionIdentifier,
           actionIdentifier != UNNotificationDismissActionIdentifier {
            emit(event: "$push_action_clicked", message: msg, actionButton: actionIdentifier)
            lock.lock()
            let cb = handlers.onAction
            lock.unlock()
            cb?(msg, actionIdentifier)
        } else {
            emit(event: "$push_opened", message: msg)
            lock.lock()
            let cb = handlers.onOpen
            lock.unlock()
            cb?(msg)
        }
    }

    // MARK: - Internal

    private func emit(event: String, message: RitmusPushMessage, actionButton: String? = nil) {
        var props: [String: Any] = [:]
        if let c = message.campaignId { props["campaign_id"] = c }
        if let v = message.variantId { props["variant_id"] = v }
        if let d = message.deliveryId { props["delivery_id"] = d }
        if let lang = message.language { props["language"] = lang }
        if let ab = actionButton { props["action_button"] = ab }
        trackFn(event, props)
    }
}
