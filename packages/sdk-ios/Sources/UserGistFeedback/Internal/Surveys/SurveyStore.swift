import Foundation

// PORTED FROM: packages/sdk-react-native/src/internal/survey-store.ts
//
// Per-survey in-progress attempt snapshot persisted to disk so a force-
// quit mid-survey resumes at the same question on the next launch.
// Keyed by `surveyId`; only one in-flight attempt per survey is preserved.

struct SurveyAttempt: Codable, Sendable, Equatable {
    let attemptId: String
    let surveyId: String
    var answers: [String: SurveyAnswerValue]
    var currentQuestionId: String?
    let startedAt: Date
    // Optional for compatibility with snapshots written by earlier SDK builds.
    var locallyEditedQuestionIds: Set<String>? = nil
}

final class SurveyStore {
    private let storage: Storage
    private let logger: UserGistLogger
    private let queue: DispatchQueue
    private var attempts: [String: SurveyAttempt]
    private let fileURL: URL

    init(storage: Storage, logger: UserGistLogger, queue: DispatchQueue) {
        self.storage = storage
        self.logger = logger
        self.queue = queue
        self.fileURL = storage.root.appendingPathComponent("survey_attempts.json")
        self.attempts = SurveyStore.loadFromDisk(url: fileURL, storage: storage, logger: logger)
    }

    /// Returns the in-progress attempt for `surveyId`, or nil if none.
    func currentAttempt(for surveyId: String) -> SurveyAttempt? {
        queue.sync { attempts[surveyId] }
    }

    /// Begins a new attempt, overwriting any prior in-progress state.
    func begin(surveyId: String, attemptId: String, startQuestionId: String) -> SurveyAttempt {
        queue.sync {
            let attempt = SurveyAttempt(
                attemptId: attemptId,
                surveyId: surveyId,
                answers: [:],
                currentQuestionId: startQuestionId,
                startedAt: Date()
            )
            attempts[surveyId] = attempt
            persistLocked()
            return attempt
        }
    }

    /// Keeps the server-authoritative attempt ID while preserving this device's
    /// edited answers if an interrupted progress request left the server behind.
    /// The API owns attempt ids; native code must never invent one locally.
    func upsert(
        surveyId: String,
        attemptId: String,
        answers: [String: SurveyAnswerValue],
        currentQuestionId: String?
    ) -> SurveyAttempt {
        queue.sync {
            let local = attempts[surveyId].flatMap { $0.attemptId == attemptId ? $0 : nil }
            let edited = local?.locallyEditedQuestionIds ?? []
            var merged = answers
            for id in edited {
                if let value = local?.answers[id] { merged[id] = value }
            }
            let attempt = SurveyAttempt(
                attemptId: attemptId,
                surveyId: surveyId,
                answers: merged,
                currentQuestionId: edited.isEmpty ? currentQuestionId : local?.currentQuestionId,
                startedAt: local?.startedAt ?? Date(),
                locallyEditedQuestionIds: edited.isEmpty ? nil : edited
            )
            attempts[surveyId] = attempt
            persistLocked()
            return attempt
        }
    }

    /// Records an answer and updates the current question pointer.
    func recordAnswer(surveyId: String, questionId: String, value: SurveyAnswerValue, nextQuestionId: String?) {
        queue.sync {
            guard var attempt = attempts[surveyId] else { return }
            attempt.answers[questionId] = value
            if attempt.locallyEditedQuestionIds == nil { attempt.locallyEditedQuestionIds = [] }
            attempt.locallyEditedQuestionIds?.insert(questionId)
            attempt.currentQuestionId = nextQuestionId
            attempts[surveyId] = attempt
            persistLocked()
        }
    }

    /// Clears the saved attempt — called on submit or dismiss.
    func clear(surveyId: String) {
        queue.sync {
            attempts.removeValue(forKey: surveyId)
            persistLocked()
        }
    }

    func clearAll() {
        queue.sync {
            attempts.removeAll()
            persistLocked()
        }
    }

    private func persistLocked() {
        do {
            try storage.writeJSON(attempts, to: fileURL)
        } catch {
            logger.error("survey store persist failed", error: error)
        }
    }

    private static func loadFromDisk(
        url: URL,
        storage: Storage,
        logger: UserGistLogger
    ) -> [String: SurveyAttempt] {
        do {
            return try storage.readJSON([String: SurveyAttempt].self, at: url) ?? [:]
        } catch {
            logger.error("survey store hydrate failed", error: error)
            return [:]
        }
    }
}
