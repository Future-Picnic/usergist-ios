import Foundation
import UIKit

/// Resolves system defaults, the global developer theme, and the dashboard's
/// per-prompt theme into a concrete `ResolvedTheme` used by the UI layer.
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
    /// Requested family. Surfaces build exact sizes from it; system font if missing.
    var fontFamily: String? = nil

    /// SDK default theme. Matches the React Native `DEFAULT_THEME` so an app
    /// without a dashboard theme looks the same on every SDK.
    static let fallback: ResolvedTheme = {
        let family = ThemeResolver.defaultFontFamily
        return ResolvedTheme(
            primary: UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1),
            background: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
            text: UIColor(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0B / 255, alpha: 1),
            subtext: UIColor(red: 0x6B / 255, green: 0x6B / 255, blue: 0x6B / 255, alpha: 1),
            border: UIColor(red: 0xE5 / 255, green: 0xE5 / 255, blue: 0xE5 / 255, alpha: 1),
            radius: 20,
            font: ThemeResolver.font(family: family, size: 15, weight: .regular),
            titleFont: ThemeResolver.font(family: family, size: 18, weight: .bold),
            boldFont: ThemeResolver.font(family: family, size: 15, weight: .semibold),
            fontFamily: family
        )
    }()
}

enum ThemeResolver {
    static let defaultFontFamily = "Plus Jakarta Sans"

    /// Resolves the effective theme from three sources (right-most wins).
    static func resolve(
        server: PromptTheme?,
        override: PromptTheme?
    ) -> ResolvedTheme {
        let fallback = ResolvedTheme.fallback
        let sc = server?.colors
        let oc = override?.colors

        let primary = sc?.primary ?? oc?.primary
        let background = sc?.background ?? oc?.background
        let text = sc?.text ?? oc?.text
        let subtext = sc?.subtext ?? oc?.subtext
        let border = sc?.border ?? oc?.border
        let radius = server?.radius ?? override?.radius
        let fontFamily = server?.fontFamily ?? override?.fontFamily ?? defaultFontFamily

        return ResolvedTheme(
            primary: parseHex(primary) ?? fallback.primary,
            background: parseHex(background) ?? fallback.background,
            text: parseHex(text) ?? fallback.text,
            subtext: parseHex(subtext) ?? fallback.subtext,
            border: parseHex(border) ?? fallback.border,
            radius: CGFloat(radius ?? Double(fallback.radius)),
            font: font(family: fontFamily, size: 15, weight: .regular),
            titleFont: font(family: fontFamily, size: 18, weight: .bold),
            boldFont: font(family: fontFamily, size: 15, weight: .semibold),
            fontFamily: fontFamily
        )
    }

    /// Theme family at a given weight when the host app bundles it; otherwise
    /// the system font at the same size and weight.
    static func font(family: String?, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        guard let family, !family.isEmpty, !UIFont.fontNames(forFamilyName: family).isEmpty else {
            return system
        }
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        let candidate = UIFont(descriptor: descriptor, size: size)
        return candidate.familyName == family ? candidate : system
    }

    /// Parses theme colours: #rgb, #rgba, #rrggbb, #rrggbbaa, rgb() and rgba().
    static func parseHex(_ value: String?) -> UIColor? {
        SurfaceColor.parse(value)
    }
}
