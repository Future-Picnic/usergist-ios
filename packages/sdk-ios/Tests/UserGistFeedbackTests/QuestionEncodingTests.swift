import XCTest
@testable import UserGistFeedback

final class QuestionEncodingTests: XCTestCase {
    // Include every wire field, Unicode, escaping, and nested choice objects.
    private let fixtures = [
        #"{"type":"rating","id":"r","title":"Rate 🎹","subtitle":"שלום","imageUrl":"https://example.com/r.png","scale":10,"display":"numeric","lowLabel":"Low","highLabel":"High"}"#,
        #"{"type":"nps","id":"n","title":"Recommend?","subtitle":"NPS","imageUrl":"https://example.com/n.png","followUp":"Why?","lowLabel":"Never","highLabel":"Always"}"#,
        #"{"type":"multiple_choice","id":"m","title":"Pick","subtitle":"Options","imageUrl":"https://example.com/m.png","options":[{"id":"a","label":"A"},{"id":"b","label":"B"}],"multiSelect":true}"#,
        #"{"type":"short_text","id":"s","title":"Tell us","subtitle":"Text","imageUrl":"https://example.com/s.png","placeholder":"A \"quote\"\nand newline","maxLength":280}"#,
        #"{"type":"rating","id":"r-min","title":"Rate","scale":5}"#,
        #"{"type":"nps","id":"n-min","title":"Recommend?"}"#,
        #"{"type":"multiple_choice","id":"m-min","title":"Pick","options":[]}"#,
        #"{"type":"short_text","id":"s-min","title":"Tell us"}"#
    ]

    func testEveryQuestionPreservesTheExactFlatJSONContract() throws {
        for fixture in fixtures {
            let original = Data(fixture.utf8)
            let question = try JSONDecoder.usergist().decode(Question.self, from: original)
            let encoded = try JSONEncoder.usergist().encode(question)
            let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? NSDictionary)
            let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
            XCTAssertEqual(actual, expected, fixture)
            XCTAssertEqual(try JSONDecoder.usergist().decode(Question.self, from: encoded), question)
        }
    }

    func testEveryQuestionEncodesWithStrictFoundationContainers() throws {
        // Modern JSONEncoder tolerates the old keyed/single-value misuse.
        // PropertyListEncoder still traps on it, reproducing the production
        // Foundation failure on current CI without relying on an old runtime.
        for fixture in fixtures {
            let question = try JSONDecoder.usergist().decode(Question.self, from: Data(fixture.utf8))
            for format: PropertyListSerialization.PropertyListFormat in [.binary, .xml] {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = format
                let encoded = try encoder.encode(question)
                XCTAssertEqual(try PropertyListDecoder().decode(Question.self, from: encoded), question)
            }
        }
    }

    func testRatingStylesAndExplicitNullOptionalsRoundTrip() throws {
        for display in ["null", "\"stars\"", "\"numeric\"", "\"emoji\""] {
            let json = """
            {"type":"rating","id":"r","title":"Rate","scale":5,"display":\(display),
             "subtitle":null,"imageUrl":null,"lowLabel":null,"highLabel":null,"futureField":true}
            """
            let question = try JSONDecoder.usergist().decode(Question.self, from: Data(json.utf8))
            XCTAssertEqual(try JSONDecoder.usergist().decode(Question.self,
                from: JSONEncoder.usergist().encode(question)), question)
        }
    }

    func testArmedTriggersPersistAndRestoreCompleteQuestionsAcrossColdStarts() throws {
        let storage = try makeStorage()
        let triggers = try makeTriggers()
        let cache = makeCache(storage)
        // Multiple syncs must remain safe, including repeated questions.
        for _ in 0..<3 { cache.replace(triggers + triggers) }
        XCTAssertEqual(cache.snapshot(), triggers + triggers)
        XCTAssertEqual(makeCache(storage).snapshot(), triggers + triggers)
        XCTAssertEqual(makeCache(storage).triggers(for: "$app_open"), triggers + triggers)
        cache.replace([])
        XCTAssertEqual(makeCache(storage).snapshot(), [])
    }

    func testCorruptOrUnsupportedCachedQuestionsDoNotPreventStartupOrRecovery() throws {
        let storage = try makeStorage()
        let triggers = try makeTriggers()
        let valid = try JSONEncoder.usergist().encode(triggers)
        let unknownType = String(decoding: valid, as: UTF8.self)
            .replacingOccurrences(of: "short_text", with: "future_question")
        for corrupt in [Data(), Data("{".utf8), Data("null".utf8), Data(unknownType.utf8)] {
            try storage.writeData(corrupt, to: storage.armedTriggersFile)
            let cache = makeCache(storage)
            XCTAssertTrue(cache.snapshot().isEmpty)
            cache.replace(triggers)
            XCTAssertEqual(makeCache(storage).snapshot(), triggers)
        }
    }

    func testDiskWriteFailureKeepsPromptsUsableInMemory() throws {
        let storage = try makeStorage()
        // A directory at the file path deterministically simulates a write
        // failure without relying on permissions or filling the device disk.
        try FileManager.default.createDirectory(at: storage.armedTriggersFile,
            withIntermediateDirectories: true)
        let triggers = try makeTriggers()
        let cache = makeCache(storage)
        cache.replace(triggers)
        XCTAssertEqual(cache.snapshot(), triggers)
        XCTAssertEqual(cache.triggers(for: "$app_open"), triggers)
    }

    func testEncodingFailureDoesNotOverwriteAnExistingCache() throws {
        let storage = try makeStorage()
        let triggers = try makeTriggers()
        try storage.writeJSON(triggers, to: storage.armedTriggersFile)
        let previous = try Data(contentsOf: storage.armedTriggersFile)
        XCTAssertThrowsError(try storage.writeJSON(FailingPayload(), to: storage.armedTriggersFile))
        XCTAssertEqual(try Data(contentsOf: storage.armedTriggersFile), previous)
        XCTAssertEqual(makeCache(storage).snapshot(), triggers)
    }

    func testInvalidQuestionPayloadsThrowInsteadOfTrapping() {
        for json in [
            #"{"type":"future_question","id":"q","title":"Q"}"#,
            #"{"type":"short_text","title":"Missing ID"}"#,
            #"{"type":"rating","id":"q","title":"Q","scale":"five"}"#,
            #"{"type":"multiple_choice","id":"q","title":"Q","options":null}"#,
            #"{"id":"q","title":"Missing type"}"#
        ] {
            XCTAssertThrowsError(try JSONDecoder.usergist().decode(Question.self, from: Data(json.utf8)))
        }
    }

    private func makeTriggers() throws -> [ArmedTrigger] {
        let json = """
        [{"promptId":"p","eventName":"$app_open","frequency":{},
          "prompt":{"id":"p","questions":[\(fixtures.joined(separator: ","))]}}]
        """
        return try JSONDecoder.usergist().decode([ArmedTrigger].self, from: Data(json.utf8))
    }

    private func makeStorage() throws -> Storage {
        try Storage(writeKeyHash: "encoding-regression-\(UUID().uuidString)")
    }

    private func makeCache(_ storage: Storage) -> RulesCache {
        RulesCache(storage: storage, logger: UserGistLogger(debug: false),
            queue: DispatchQueue(label: "encoding-regression-cache"))
    }

    private struct FailingPayload: Encodable {
        func encode(to encoder: Encoder) throws {
            throw EncodingError.invalidValue("test", .init(codingPath: encoder.codingPath,
                debugDescription: "Simulated encoding failure"))
        }
    }
}
