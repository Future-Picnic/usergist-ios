import XCTest
@testable import UserGistFeedback

final class SegmentEvaluatorTests: XCTestCase {
    func test_nilRulesAlwaysMatches() {
        XCTAssertTrue(SegmentEvaluator.evaluate(nil, user: .empty))
    }

    func test_userPropertyEquals() {
        let rules = SerializedSegmentRules(
            userProperties: [
                .init(key: "plan", op: "eq", value: .string("pro"))
            ],
            eventCounts: nil
        )
        let user = UserState(
            properties: ["plan": .string("pro")],
            eventCounts: [:],
            lastEventAt: [:]
        )
        XCTAssertTrue(SegmentEvaluator.evaluate(rules, user: user))

        let userFree = UserState(
            properties: ["plan": .string("free")],
            eventCounts: [:],
            lastEventAt: [:]
        )
        XCTAssertFalse(SegmentEvaluator.evaluate(rules, user: userFree))
    }

    func test_userPropertyInList() {
        let rules = SerializedSegmentRules(
            userProperties: [
                .init(
                    key: "country",
                    op: "in",
                    value: .list([.string("DE"), .string("FR"), .string("NL")])
                )
            ],
            eventCounts: nil
        )
        let userMatch = UserState(
            properties: ["country": .string("DE")],
            eventCounts: [:],
            lastEventAt: [:]
        )
        let userMiss = UserState(
            properties: ["country": .string("US")],
            eventCounts: [:],
            lastEventAt: [:]
        )
        XCTAssertTrue(SegmentEvaluator.evaluate(rules, user: userMatch))
        XCTAssertFalse(SegmentEvaluator.evaluate(rules, user: userMiss))
    }

    func test_userPropertyNumericComparisons() {
        let rules = SerializedSegmentRules(
            userProperties: [
                .init(key: "checkouts", op: "gte", value: .number(3))
            ],
            eventCounts: nil
        )
        let user = UserState(
            properties: ["checkouts": .number(5)],
            eventCounts: [:],
            lastEventAt: [:]
        )
        XCTAssertTrue(SegmentEvaluator.evaluate(rules, user: user))

        let userLow = UserState(
            properties: ["checkouts": .number(2)],
            eventCounts: [:],
            lastEventAt: [:]
        )
        XCTAssertFalse(SegmentEvaluator.evaluate(rules, user: userLow))
    }

    func test_eventCountRule() {
        let rules = SerializedSegmentRules(
            userProperties: nil,
            eventCounts: [
                .init(eventName: "completed_checkout", op: "gte", count: 3, windowDays: 7)
            ]
        )
        let user = UserState(
            properties: [:],
            eventCounts: ["completed_checkout": [7: 4]],
            lastEventAt: [:]
        )
        XCTAssertTrue(SegmentEvaluator.evaluate(rules, user: user))

        let userLow = UserState(
            properties: [:],
            eventCounts: ["completed_checkout": [7: 2]],
            lastEventAt: [:]
        )
        XCTAssertFalse(SegmentEvaluator.evaluate(rules, user: userLow))
    }

    func test_combinedPropertyAndEventCount() {
        let rules = SerializedSegmentRules(
            userProperties: [
                .init(key: "plan", op: "eq", value: .string("free"))
            ],
            eventCounts: [
                .init(eventName: "completed_checkout", op: "gte", count: 3, windowDays: 30)
            ]
        )
        let userMatch = UserState(
            properties: ["plan": .string("free")],
            eventCounts: ["completed_checkout": [30: 5]],
            lastEventAt: [:]
        )
        XCTAssertTrue(SegmentEvaluator.evaluate(rules, user: userMatch))

        let wrongPlan = UserState(
            properties: ["plan": .string("pro")],
            eventCounts: ["completed_checkout": [30: 5]],
            lastEventAt: [:]
        )
        XCTAssertFalse(SegmentEvaluator.evaluate(rules, user: wrongPlan))
    }

    func test_neqOp() {
        let rules = SerializedSegmentRules(
            userProperties: [
                .init(key: "role", op: "neq", value: .string("admin"))
            ],
            eventCounts: nil
        )
        let user = UserState(
            properties: ["role": .string("member")],
            eventCounts: [:],
            lastEventAt: [:]
        )
        XCTAssertTrue(SegmentEvaluator.evaluate(rules, user: user))

        let admin = UserState(
            properties: ["role": .string("admin")],
            eventCounts: [:],
            lastEventAt: [:]
        )
        XCTAssertFalse(SegmentEvaluator.evaluate(rules, user: admin))
    }
}
