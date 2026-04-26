import Foundation
import UIKit

/// Merges server prompt theme, developer override, and system defaults
/// into a concrete `ResolvedTheme` used by the UI layer.
struct ResolvedTheme {
    let primary: UIColor
    let background: UIColor
    let text: UIColor
    let subtext: UIColor
    let border: UIColor
    let radius: CGFloat
    let font: UIFont
    let titleFont: UIFont
    let boldFont: UIFont

    static let fallback: ResolvedTheme = {
        let body = UIFont.systemFont(ofSize: 15, weight: .regular)
        let title = UIFont.systemFont(ofSize: 18, weight: .semibold)
        let bold = UIFont.systemFont(ofSize: 15, weight: .semibold)
        return ResolvedTheme(
            primary: UIColor.systemBlue,
            background: UIColor.systemBackground,
            text: UIColor.label,
            subtext: UIColor.secondaryLabel,
            border: UIColor.separator,
            radius: 16,
            font: body,
            titleFont: title,
            boldFont: bold
        )
    }()
}

enum ThemeResolver {
    /// Resolves the effective theme from three sources (right-most wins).
    static func resolve(
        server: PromptTheme?,
        override: PromptTheme?
    ) -> ResolvedTheme {
        let fallback = ResolvedTheme.fallback
        let sc = server?.colors
        let oc = override?.colors

        let primary = oc?.primary ?? sc?.primary
        let background = oc?.background ?? sc?.background
        let text = oc?.text ?? sc?.text
        let subtext = oc?.subtext ?? sc?.subtext
        let border = oc?.border ?? sc?.border
        let radius = override?.radius ?? server?.radius
        let fontFamily = override?.fontFamily ?? server?.fontFamily ?? "Plus Jakarta Sans"

        let bodyFont = buildFont(family: fontFamily, size: 15, weight: .regular, fallback: fallback.font)
        let titleFont = buildFont(family: fontFamily, size: 18, weight: .semibold, fallback: fallback.titleFont)
        let boldFont = buildFont(family: fontFamily, size: 15, weight: .semibold, fallback: fallback.boldFont)

        return ResolvedTheme(
            primary: parseHex(primary) ?? fallback.primary,
            background: parseHex(background) ?? fallback.background,
            text: parseHex(text) ?? fallback.text,
            subtext: parseHex(subtext) ?? fallback.subtext,
            border: parseHex(border) ?? fallback.border,
            radius: CGFloat(radius ?? Double(fallback.radius)),
            font: bodyFont,
            titleFont: titleFont,
            boldFont: boldFont
        )
    }

    private static func buildFont(
        family: String?,
        size: CGFloat,
        weight: UIFont.Weight,
        fallback: UIFont
    ) -> UIFont {
        guard let family, !family.isEmpty else { return fallback }
        if let descriptor = UIFont(name: family, size: size) {
            // Build a weight-adjusted font via trait attributes.
            let traits = [UIFontDescriptor.TraitKey.weight: weight]
            let attributes: [UIFontDescriptor.AttributeName: Any] = [
                .name: family,
                .traits: traits
            ]
            let desc = UIFontDescriptor(fontAttributes: attributes)
            return UIFont(descriptor: desc, size: size).withSize(size).withFamilyFallback(descriptor)
        }
        return fallback
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA` hex to a `UIColor`.
    static func parseHex(_ value: String?) -> UIColor? {
        guard var hex = value else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8 else { return nil }
        guard let int = UInt64(hex, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if hex.count == 6 {
            r = CGFloat((int >> 16) & 0xFF) / 255.0
            g = CGFloat((int >> 8) & 0xFF) / 255.0
            b = CGFloat(int & 0xFF) / 255.0
            a = 1.0
        } else {
            r = CGFloat((int >> 24) & 0xFF) / 255.0
            g = CGFloat((int >> 16) & 0xFF) / 255.0
            b = CGFloat((int >> 8) & 0xFF) / 255.0
            a = CGFloat(int & 0xFF) / 255.0
        }
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

private extension UIFont {
    func withFamilyFallback(_ fallback: UIFont) -> UIFont {
        self.familyName.isEmpty ? fallback : self
    }
}
