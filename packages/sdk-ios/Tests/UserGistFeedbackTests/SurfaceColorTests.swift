import XCTest
import UIKit
@testable import UserGistFeedback

/// Parity with packages/sdk-react-native/src/ui/color.test.ts.
final class SurfaceColorTests: XCTestCase {
    private func color(_ value: String) throws -> UIColor {
        try XCTUnwrap(SurfaceColor.parse(value), "Expected \(value) to parse")
    }

    private func ratio(_ background: UIColor, _ foreground: UIColor) -> CGFloat {
        SurfaceColor.contrastRatio(SurfaceColor.relativeLuminance(background),
                                   SurfaceColor.relativeLuminance(foreground))
    }

    func testPicksBlackOnOrangeBecauseWhiteIsOnlyAboutThreeToOne() throws {
        let orange = try color("#D97706")
        XCTAssertEqual(SurfaceColor.readableOn(orange), .black)
        XCTAssertGreaterThan(ratio(orange, .black), ratio(orange, .white))
    }

    func testPicksTheHigherContrastLabelForMidtones() throws {
        for hex in ["#7C3AED", "#2563EB", "#16A34A", "#E11D48", "#0D9488", "#808080"] {
            let background = try color(hex)
            let chosen = SurfaceColor.readableOn(background)
            let other: UIColor = chosen == .black ? .white : .black
            XCTAssertGreaterThanOrEqual(ratio(background, chosen), ratio(background, other), hex)
        }
    }

    func testUsesBlackOnLightAndWhiteOnDarkPrimaries() throws {
        for hex in ["#FACC15", "#5EEAD4", "#FFFFFF"] {
            XCTAssertEqual(SurfaceColor.readableOn(try color(hex)), .black, hex)
        }
        for hex in ["#111111", "#3B1764"] {
            XCTAssertEqual(SurfaceColor.readableOn(try color(hex)), .white, hex)
        }
    }

    func testAcceptsShortAlphaAndFunctionalFormats() throws {
        XCTAssertEqual(SurfaceColor.readableOn(try color("#fff")), .black)
        XCTAssertEqual(SurfaceColor.readableOn(try color("#000f")), .white)
        XCTAssertEqual(SurfaceColor.readableOn(try color("#D97706FF")), .black)
        XCTAssertEqual(SurfaceColor.readableOn(try color("rgb(17, 17, 17)")), .white)
        XCTAssertEqual(SurfaceColor.readableOn(try color("rgba(250,204,21,0.9)")), .black)
        var alpha: CGFloat = 0
        try color("#11223380").getRed(nil, green: nil, blue: nil, alpha: &alpha)
        XCTAssertEqual(alpha, 128.0 / 255.0, accuracy: 0.001)
    }

    func testRejectsUnsupportedValues() {
        for value in ["purple", "#12", "hsl(0,0%,0%)", "rgb(300,0,0)", "", "#GGGGGG"] {
            XCTAssertNil(SurfaceColor.parse(value), value)
        }
        // Theme resolution falls back to the SDK default for unparseable colours.
        let resolved = ThemeResolver.resolve(server: PromptTheme(colors: .init(primary: "purple")), override: nil)
        XCTAssertEqual(resolved.primary, ResolvedTheme.fallback.primary)
    }

    func testSurfaceTokensDeriveFromThemeColours() throws {
        let theme = ThemeResolver.resolve(server: PromptTheme(colors: .init(
            primary: "#FACC15", background: "#111111", text: "#F5F5F5"
        )), override: nil)
        XCTAssertEqual(theme.onPrimary, .black)
        XCTAssertEqual(theme.tint, theme.primary.withAlphaComponent(0.1))
        XCTAssertEqual(theme.fill, theme.text.withAlphaComponent(0.06))
        XCTAssertEqual(theme.interfaceStyle, .dark)
        XCTAssertEqual(ResolvedTheme.fallback.interfaceStyle, .light)
    }

    func testDefaultThemeMatchesReactNative() {
        let theme = ResolvedTheme.fallback
        XCTAssertEqual(theme.primary, SurfaceColor.parse("#111111"))
        XCTAssertEqual(theme.background, SurfaceColor.parse("#FFFFFF"))
        XCTAssertEqual(theme.text, SurfaceColor.parse("#0B0B0B"))
        XCTAssertEqual(theme.subtext, SurfaceColor.parse("#6B6B6B"))
        XCTAssertEqual(theme.border, SurfaceColor.parse("#E5E5E5"))
        XCTAssertEqual(theme.radius, 20)
    }
}
