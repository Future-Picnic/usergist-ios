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

    /// Persists the server-authoritative attempt returned by create/resume.
    /// The API owns attempt ids; native code must never invent one locally.
    func upsert(
        surveyId: String,
        attemptId: String,
        answers: [String: SurveyAnswerValue],
        currentQuestionId: String?
    ) -> SurveyAttempt {
        queue.sync {
            let attempt = SurveyAttempt(
                attemptId: attemptId,
                surveyId: surveyId,
                answers: answers,
                currentQuestionId: currentQuestionId,
                startedAt: attempts[surveyId]?.startedAt ?? Date()
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
