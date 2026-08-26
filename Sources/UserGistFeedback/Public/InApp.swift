import Foundation

/// Presentation requested by an authenticated in-app message instruction.
public enum InAppMessageFormat: String, Codable, Sendable {
    case modal
    case modalFull = "modal_full"
    case slideup
}

/// Action attached to an in-app message button.
public enum InAppCtaAction: String, Codable, Sendable {
    case openURL = "open_url"
    case deepLink = "deep_link"
    case dismiss
    case customEvent = "custom_event"
}

public struct InAppCta: Codable, Sendable, Equatable {
    public let label: String
    public let action: InAppCtaAction
    public let target: String?

    public init(label: String, action: InAppCtaAction, target: String? = nil) {
        self.label = label
        self.action = action
        self.target = target
    }
}

/// Runtime subset of an in-app campaign sent through the durable SDK inbox.
public struct ArmedInAppMessage: Codable, Sendable, Equatable {
    public let messageId: String
    public let eventName: String
    public let clientSideEligible: Bool?
    public let format: InAppMessageFormat
    public let title: String
    public let body: String?
    public let imageUrl: String?
    public let backgroundColor: String?
    public let accentColor: String?
    public let backdropEnabled: Bool
    public let ctas: [InAppCta]
    public let autoDismissSeconds: Double?
    public let screenAllowlist: [String]
    public let screenDenylist: [String]
    public let forceShow: Bool

    private enum CodingKeys: String, CodingKey {
        case messageId, eventName, clientSideEligible, format, title, body
        case imageUrl, backgroundColor, accentColor, backdropEnabled, ctas
        case autoDismissSeconds, screenAllowlist, screenDenylist, forceShow
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messageId = try c.decode(String.self, forKey: .messageId)
        eventName = try c.decodeIfPresent(String.self, forKey: .eventName) ?? "server"
        clientSideEligible = try c.decodeIfPresent(Bool.self, forKey: .clientSideEligible)
        format = try c.decode(InAppMessageFormat.self, forKey: .format)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        backgroundColor = try c.decodeIfPresent(String.self, forKey: .backgroundColor)
        accentColor = try c.decodeIfPresent(String.self, forKey: .accentColor)
        backdropEnabled = try c.decodeIfPresent(Bool.self, forKey: .backdropEnabled) ?? true
        ctas = try c.decodeIfPresent([InAppCta].self, forKey: .ctas) ?? []
        autoDismissSeconds = try c.decodeIfPresent(Double.self, forKey: .autoDismissSeconds)
        screenAllowlist = try c.decodeIfPresent([String].self, forKey: .screenAllowlist) ?? []
        screenDenylist = try c.decodeIfPresent([String].self, forKey: .screenDenylist) ?? []
        forceShow = try c.decodeIfPresent(Bool.self, forKey: .forceShow) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(messageId, forKey: .messageId)
        try c.encode(eventName, forKey: .eventName)
        try c.encodeIfPresent(clientSideEligible, forKey: .clientSideEligible)
        try c.encode(format, forKey: .format)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(body, forKey: .body)
        try c.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try c.encodeIfPresent(backgroundColor, forKey: .backgroundColor)
        try c.encodeIfPresent(accentColor, forKey: .accentColor)
        try c.encode(backdropEnabled, forKey: .backdropEnabled)
        try c.encode(ctas, forKey: .ctas)
        try c.encodeIfPresent(autoDismissSeconds, forKey: .autoDismissSeconds)
        try c.encode(screenAllowlist, forKey: .screenAllowlist)
        try c.encode(screenDenylist, forKey: .screenDenylist)
        try c.encode(forceShow, forKey: .forceShow)
    }
}

struct ArmedInAppMessagesResponse: Codable {
    let messages: [ArmedInAppMessage]
    let serverTime: String?
    let nextSyncMs: Int?
}

public enum InAppDismissReason: String, Sendable {
    case user
    case auto
}

public struct InAppCtaClick: Sendable, Equatable {
    public let messageId: String
    public let action: InAppCtaAction
    public let target: String?
    public let label: String
    public let index: Int
}

/// Optional lifecycle callbacks for SDK-rendered in-app messages.
public struct InAppHandlers {
    public var onShow: ((String) -> Void)?
    public var onDismiss: ((String, InAppDismissReason) -> Void)?
    public var onCtaClick: ((InAppCtaClick) -> Void)?

    public init(
        onShow: ((String) -> Void)? = nil,
        onDismiss: ((String, InAppDismissReason) -> Void)? = nil,
        onCtaClick: ((InAppCtaClick) -> Void)? = nil
    ) {
        self.onShow = onShow
        self.onDismiss = onDismiss
        self.onCtaClick = onCtaClick
    }
}
