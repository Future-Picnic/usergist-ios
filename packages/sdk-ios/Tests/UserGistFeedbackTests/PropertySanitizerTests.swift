import XCTest
@testable import UserGistFeedback

final class PropertySanitizerTests: XCTestCase {
    func test_eventPropertiesMatchReferenceBoundsAndScalarContract() {
        let clean = AnyCodable.wrapEventProperties([
            "plan": "pro",
            "account.email": "private@example.com",
            "nested": ["bad": true],
            "list": [1, 2],
            "score": 4.5,
            "enabled": true,
            "nothing": NSNull(),
            "long": String(repeating: "x", count: 10_001)
        ])

        XCTAssertEqual(clean?["plan"], AnyCodable("pro"))
        XCTAssertEqual(clean?["score"], AnyCodable(4.5))
        XCTAssertEqual(clean?["enabled"], AnyCodable(true))
        XCTAssertEqual(clean?["nothing"], AnyCodable(nil))
        XCTAssertEqual((clean?["long"]?.value as? String)?.count, 10_000)
        XCTAssertNil(clean?["account.email"])
        XCTAssertNil(clean?["nested"])
        XCTAssertNil(clean?["list"])
        XCTAssertLessThanOrEqual(clean?.count ?? 0, 100)
    }
}
