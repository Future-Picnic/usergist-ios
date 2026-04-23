import Foundation
import UIKit

/// Visual overrides applied to rendered feedback prompts.
///
/// These values are merged with the server-supplied prompt theme and the
/// system defaults. Any `nil` field falls back to the prompt or system
/// default.
public struct PromptTheme: Codable, Equatable, Sendable {
    public struct Colors: Codable, Equatable, Sendable {
        /// Hex string (`#RRGGBB` or `#RRGGBBAA`) for primary/accent color.
        public var primary: String?
        /// Hex string for the sheet background.
        public var background: String?
        /// Hex string for primary text.
        public var text: String?
        /// Hex string for secondary / subtitle text.
        public var subtext: String?
        /// Hex string for borders / separators.
        public var border: String?

        public init(
            primary: String? = nil,
            background: String? = nil,
            text: String? = nil,
            subtext: String? = nil,
            border: String? = nil
        ) {
            self.primary = primary
            self.background = background
            self.text = text
            self.subtext = subtext
            self.border = border
        }
    }

    public var colors: Colors?
    /// Corner radius applied to the bottom sheet and primary controls.
    public var radius: Double?
    /// Font family name used for prompt text. Must be installed in the host app.
    public var fontFamily: String?

    public init(
        colors: Colors? = nil,
        radius: Double? = nil,
        fontFamily: String? = nil
    ) {
        self.colors = colors
        self.radius = radius
        self.fontFamily = fontFamily
    }
}
