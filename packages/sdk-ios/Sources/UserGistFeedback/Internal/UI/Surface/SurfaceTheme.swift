import Foundation
import UIKit

// PORTED FROM: packages/sdk-react-native/src/ui/color.ts + theme.ts
//
// One token system for every UserGist surface. All extra colours derive from
// the five campaign colours, so any dashboard theme (light, dark, pastel or
// saturated) stays legible without fixed greys or white.

/// Pure colour helpers. No view code, so they are unit-tested directly.
enum SurfaceColor {
    /// Parses #rgb, #rgba, #rrggbb, #rrggbbaa and rgb()/rgba(). Returns nil
    /// for anything else (named colours, hsl, malformed input).
    static func parse(_ input: String?) -> UIColor? {
        guard let raw = input?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("#") { return parseHex(String(raw.dropFirst())) }
        return parseFunctional(raw)
    }

    private static func parseHex(_ hex: String) -> UIColor? {
        guard [3, 4, 6, 8].contains(hex.count),
              hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        let full = hex.count <= 4 ? hex.map { "\($0)\($0)" }.joined() : hex
        guard let value = UInt64(full, radix: 16) else { return nil }
        let hasAlpha = full.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        let r = CGFloat((value >> (16 + shift)) & 0xFF) / 255
        let g = CGFloat((value >> (8 + shift)) & 0xFF) / 255
        let b = CGFloat((value >> shift) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    private static func parseFunctional(_ value: String) -> UIColor? {
        let lower = value.lowercased()
        guard lower.hasPrefix("rgb"), let open = lower.firstIndex(of: "("),
              lower.hasSuffix(")") else { return nil }
        let inner = lower[lower.index(after: open)..<lower.index(before: lower.endIndex)]
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let channels = parts.prefix(3).compactMap { Int($0) }
        guard channels.count == 3, channels.allSatisfy({ (0...255).contains($0) }) else { return nil }
        var alpha: CGFloat = 1
        if parts.count == 4 {
            guard let parsed = Double(parts[3]), parsed >= 0 else { return nil }
            alpha = CGFloat(min(parsed, 1))
        }
        return UIColor(red: CGFloat(channels[0]) / 255, green: CGFloat(channels[1]) / 255,
                       blue: CGFloat(channels[2]) / 255, alpha: alpha)
    }

    /// WCAG relative luminance. Alpha is ignored, as in the RN helper.
    static func relativeLuminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let resolved = color.resolvedColor(with: UITraitCollection.current)
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            var white: CGFloat = 0
            resolved.getWhite(&white, alpha: &a)
            return linear(white)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private static func linear(_ channel: CGFloat) -> CGFloat {
        let c = min(max(channel, 0), 1)
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// WCAG contrast ratio between two luminances (1–21).
    static func contrastRatio(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let hi = max(a, b), lo = min(a, b)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Black or white, whichever has the greater real contrast on `background`.
    static func readableOn(_ background: UIColor) -> UIColor {
        let lum = relativeLuminance(background)
        return contrastRatio(lum, 0) > contrastRatio(lum, 1) ? .black : .white
    }
}

/// Shared measurements (points). Mirrors `SurfaceControls.tsx`.
enum SurfaceMetrics {
    /// Readable measure: sheet backgrounds span the full width, content stays within this.
    static let contentMaxWidth: CGFloat = 560
    static let iconHit: CGFloat = 44
    static let iconFace: CGFloat = 32
    static let headerMinHeight: CGFloat = 48
    static let primaryMinHeight: CGFloat = 50
    static let compactMinHeight: CGFloat = 44
    static let compactMinWidth: CGFloat = 88
    static let trailingMaxWidth: CGFloat = 320
    static let balancedHeaderSide: CGFloat = iconHit * 2 + 8
}

/// Survey/feedback landscape opts into the larger face; other surfaces retain
/// the small face and every size keeps the native 44pt touch target.
enum SurfaceIconSize {
    case small, regular

    var face: CGFloat { self == .regular ? SurfaceMetrics.compactMinHeight : SurfaceMetrics.iconFace }
    var glyphScale: CGFloat { self == .regular ? 16 / 13 : 1 }
    var stroke: CGFloat { self == .regular ? 2 : 1.75 }
}

extension ResolvedTheme {
    /// Readable label colour on a primary fill (black or white by contrast).
    var onPrimary: UIColor { SurfaceColor.readableOn(primary) }
    /// Quiet primary wash for selected options.
    var tint: UIColor { primary.withAlphaComponent(0.1) }
    /// Neutral wash for inputs and disabled actions.
    var fill: UIColor { text.withAlphaComponent(0.06) }
    /// Slightly stronger neutral, for pressed states and progress tracks.
    var fillStrong: UIColor { text.withAlphaComponent(0.12) }
    /// Face of the Close/Back controls.
    var iconFace: UIColor { text.withAlphaComponent(0.08) }
    /// Outline of secondary actions.
    var quietOutline: UIColor { text.withAlphaComponent(0.16) }
    var disabledLabel: UIColor { text.withAlphaComponent(0.38) }
    var scrim: UIColor { UIColor.black.withAlphaComponent(0.45) }

    /// Theme font at an explicit size and weight, scaled for Dynamic Type.
    func surfaceFont(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        let base = ThemeResolver.font(family: fontFamily, size: size, weight: weight)
        return UIFontMetrics.default.scaledFont(for: base, maximumPointSize: size * 2)
    }

    /// System chrome (status bar, keyboard, date picker) follows the theme
    /// background, so a dark campaign never gets light system controls.
    var interfaceStyle: UIUserInterfaceStyle {
        SurfaceColor.readableOn(background) == .white ? .dark : .light
    }

    /// Corner radius for a control, capped so large theme radii stay usable.
    func cappedRadius(_ cap: CGFloat) -> CGFloat { min(radius, cap) }
}
