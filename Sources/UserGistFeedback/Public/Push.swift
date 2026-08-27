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
public struct UserGistPushMessage: Sendable {
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

    /// Attempts to parse a UserGist push message out of an APNs userInfo
    /// dictionary. Returns `nil` if the payload doesn't contain the UserGist
    /// envelope.
    public static func parse(userInfo: [AnyHashable: Any]) -> UserGistPushMessage? {
        guard let usergist = userInfo["usergist"] as? [String: Any] else { return nil }
        let aps = userInfo["aps"] as? [String: Any]
        let alert = aps?["alert"] as? [String: Any]
        return UserGistPushMessage(
            campaignId: usergist["campaignId"] as? String,
            variantId: usergist["variantId"] as? String,
            deliveryId: usergist["deliveryId"] as? String,
            language: usergist["language"] as? String,
            deepLink: usergist["deepLink"] as? String,
            title: alert?["title"] as? String,
            body: alert?["body"] as? String
        )
    }
}

/// Callback surface for received / opened / action-tapped pushes.
public struct PushHandlers: Sendable {
    public var onReceive: (@Sendable (UserGistPushMessage, [AnyHashable: Any]) -> Void)?
    public var onOpen: (@Sendable (UserGistPushMessage) -> Void)?
    public var onAction: (@Sendable (UserGistPushMessage, String) -> Void)?
    public var onDismiss: (@Sendable (UserGistPushMessage) -> Void)?
    public var onSilent: (@Sendable (String) -> Void)?
    public var onEvent: (@Sendable (String, [String: Any]) -> Void)?

    public init(
        onReceive: (@Sendable (UserGistPushMessage, [AnyHashable: Any]) -> Void)? = nil,
        onOpen: (@Sendable (UserGistPushMessage) -> Void)? = nil,
        onAction: (@Sendable (UserGistPushMessage, String) -> Void)? = nil,
        onDismiss: (@Sendable (UserGistPushMessage) -> Void)? = nil,
        onSilent: (@Sendable (String) -> Void)? = nil,
        onEvent: (@Sendable (String, [String: Any]) -> Void)? = nil
    ) {
        self.onReceive = onReceive
        self.onOpen = onOpen
        self.onAction = onAction
        self.onDismiss = onDismiss
        self.onSilent = onSilent
        self.onEvent = onEvent
    }
}

/// Server-defined channel metadata. Hosts map this to
/// UNNotificationCategory or their own notification settings UI.
public struct UserGistPushChannel: Codable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let description: String?
    public let importance: Int
    public let defaultSound: String?
    public let defaultVibrate: Bool
    public let defaultBadge: Bool
    public let category: String

    private enum CodingKeys: String, CodingKey {
        case id = "channel_id"
        case displayName = "display_name"
        case description
        case importance
        case defaultSound = "default_sound"
        case defaultVibrate = "default_vibrate"
        case defaultBadge = "default_badge"
        case category
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
/// UserGist.shared.push.didReceiveDeviceToken(deviceToken)
///
/// // In UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:...)
/// UserGist.shared.push.handleReceived(userInfo: notification.request.content.userInfo)
///
/// // In UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)
/// UserGist.shared.push.handleOpened(userInfo: response.notification.request.content.userInfo,
///                                  actionIdentifier: response.actionIdentifier)
/// ```
public final class UserGistPush {
    private let registerTokenFn: (String) -> Void
    private let invalidateTokenFn: (String) -> Void
    private let rebindTokenFn: (String) -> Void
    private let trackFn: (String, [String: Any]?) -> Void
    private let appOpenFn: () -> Void
    private let beaconFn: (PushBeaconKind, String, String?) -> Void
    private let silentAckFn: (String) -> Void
    private let fetchChannelsFn: (@escaping ([UserGistPushChannel]) -> Void) -> Void
    private let setChannelSubscriptionFn: (String, Bool) -> Void
    private let lock = NSLock()
    private var handlers: PushHandlers = PushHandlers()
    private var cachedToken: String?

    init(
        registerToken: @escaping (String) -> Void,
        invalidateToken: @escaping (String) -> Void = { _ in },
        rebindToken: @escaping (String) -> Void = { _ in },
        track: @escaping (String, [String: Any]?) -> Void,
        appOpen: @escaping () -> Void = {},
        beacon: @escaping (PushBeaconKind, String, String?) -> Void = { _, _, _ in },
        silentAck: @escaping (String) -> Void = { _ in },
        fetchChannels: @escaping (@escaping ([UserGistPushChannel]) -> Void) -> Void = { $0([]) },
        setChannelSubscription: @escaping (String, Bool) -> Void = { _, _ in }
    ) {
        self.registerTokenFn = registerToken
        self.invalidateTokenFn = invalidateToken
        self.rebindTokenFn = rebindToken
        self.trackFn = track
        self.appOpenFn = appOpen
        self.beaconFn = beacon
        self.silentAckFn = silentAck
        self.fetchChannelsFn = fetchChannels
        self.setChannelSubscriptionFn = setChannelSubscription
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

    /// Provisional authorization (iOS 12+). Opts the user in to *quiet*
    /// notifications (Notification Center only, no banner) without an
    /// up-front prompt. Lets us deliver low-stakes pushes and earn the
    /// upgrade to full alerts when the user explicitly promotes us.
    @available(iOS 12.0, *)
    public func requestProvisionalAuthorization(
        completion: ((PushPermissionStatus) -> Void)? = nil
    ) {
        #if canImport(UserNotifications)
        var options: UNAuthorizationOptions = [.alert, .sound, .badge]
        options.insert(.provisional)
        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    #if canImport(UIKit)
                    UIApplication.shared.registerForRemoteNotifications()
                    #endif
                }
                completion?(granted ? .provisional : .denied)
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

    /// Forward applicationDidBecomeActive (or your scene equivalent) so
    /// the server's adaptive reachability worker knows this device is
    /// alive. Skips silent-ping cycles for the next 24h on this device.
    public func appDidBecomeActive() {
        appOpenFn()
    }

    public func invalidateDeviceToken(_ token: String) {
        guard !token.isEmpty else { return }
        invalidateTokenFn(token)
    }

    public func rebindDeviceToken(externalId: String) {
        guard !externalId.isEmpty else { return }
        rebindTokenFn(externalId)
    }

    public func fetchChannels(completion: @escaping ([UserGistPushChannel]) -> Void) {
        fetchChannelsFn(completion)
    }

    public func setChannelSubscription(channelId: String, subscribed: Bool) {
        guard !channelId.isEmpty else { return }
        setChannelSubscriptionFn(channelId, subscribed)
    }

    /// Returns true for a silent reachability ping; hosts must not display it.
    @discardableResult
    public func handleSilentIfPresent(userInfo: [AnyHashable: Any]) -> Bool {
        guard (userInfo["usergist_silent"] as? String) == "1" else { return false }
        let pingId = (userInfo["usergist_ping_id"] as? String) ?? ""
        if !pingId.isEmpty {
            lock.lock()
            let callback = handlers.onSilent
            lock.unlock()
            callback?(pingId)
            silentAckFn(pingId)
        }
        return true
    }

    /// Beacon: SDK observed delivery in main process (foreground or
    /// background). The Notification Service Extension fires its own
    /// beacon earlier; calling both is safe — beacons are idempotent.
    public func beaconDelivered(deliveryId: String) {
        beaconFn(.delivered, deliveryId, nil)
    }

    /// Beacon: SDK rendered the notification UI.
    public func beaconDisplayed(deliveryId: String) {
        beaconFn(.displayed, deliveryId, nil)
    }

    /// Beacon: user dismissed the notification without opening (iOS
    /// `UNNotificationDismissActionIdentifier`).
    public func beaconDismissed(deliveryId: String) {
        beaconFn(.dismissed, deliveryId, nil)
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
        guard let msg = UserGistPushMessage.parse(userInfo: userInfo) else { return }
        emit(event: "$push_received", message: msg)
        lock.lock()
        let cb = handlers.onReceive
        lock.unlock()
        cb?(msg, userInfo)
    }

    /// Call from `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)`.
    public func handleOpened(userInfo: [AnyHashable: Any], actionIdentifier: String? = nil) {
        guard let msg = UserGistPushMessage.parse(userInfo: userInfo) else { return }
        if actionIdentifier == UNNotificationDismissActionIdentifier {
            emit(event: "$push_dismissed", message: msg)
            if let deliveryId = msg.deliveryId { beaconFn(.dismissed, deliveryId, nil) }
            lock.lock()
            let cb = handlers.onDismiss
            lock.unlock()
            cb?(msg)
        } else if let actionIdentifier, actionIdentifier != UNNotificationDefaultActionIdentifier {
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

    private func emit(event: String, message: UserGistPushMessage, actionButton: String? = nil) {
        var props: [String: Any] = [:]
        if let c = message.campaignId { props["campaign_id"] = c }
        if let v = message.variantId { props["variant_id"] = v }
        if let d = message.deliveryId { props["delivery_id"] = d }
        if let lang = message.language { props["language"] = lang }
        if let ab = actionButton { props["action_button"] = ab }
        trackFn(event, props)
        emitSDKEvent(name: event, properties: props)
    }

    func emitSDKEvent(name: String, properties: [String: Any]) {
        lock.lock()
        let callback = handlers.onEvent
        lock.unlock()
        callback?(name, properties)
    }
}
