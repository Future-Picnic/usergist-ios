import XCTest
import UIKit
@testable import UserGistFeedback

final class ThemeResolverTests: XCTestCase {
    func testPerPromptThemeWinsWhileGlobalThemeFillsMissingFields() {
        let global = PromptTheme(
            colors: .init(
                primary: "#111111",
                background: "#FFFFFF",
                text: "#222222",
                subtext: "#333333",
                border: "#444444"
            ),
            radius: 16,
            fontFamily: "Global Font"
        )
        let prompt = PromptTheme(
            colors: .init(
                primary: "#6548E8",
                background: "#F7F5FF",
                text: "#1D1933"
            ),
            radius: 24
        )

        let resolved = ThemeResolver.resolve(server: prompt, override: global)

        XCTAssertEqual(resolved.primary, ThemeResolver.parseHex("#6548E8"))
        XCTAssertEqual(resolved.background, ThemeResolver.parseHex("#F7F5FF"))
        XCTAssertEqual(resolved.text, ThemeResolver.parseHex("#1D1933"))
        XCTAssertEqual(resolved.subtext, ThemeResolver.parseHex("#333333"))
        XCTAssertEqual(resolved.border, ThemeResolver.parseHex("#444444"))
        XCTAssertEqual(resolved.radius, 24)
    }
}
