import Foundation

/// Durable hot-path cache for locally-evaluable surveys and in-app messages.
final class CampaignRulesCache {
    private let storage: Storage
    private let logger: UserGistLogger
    private let queue: DispatchQueue
    private var surveysByEvent: [String: [ArmedSurvey]] = [:]
    private var surveysById: [String: ArmedSurvey] = [:]
    private var allSurveys: [ArmedSurvey] = []
    private var inAppByEvent: [String: [ArmedInAppMessage]] = [:]

    init(storage: Storage, logger: UserGistLogger, queue: DispatchQueue) {
        self.storage = storage
        self.logger = logger
        self.queue = queue
        if let envelope = (try? storage.readJSON(
            ArmedSurveysResponse.self,
            at: storage.armedSurveysFile
        )) ?? nil {
            indexSurveys(envelope.surveys)
        }
        if let envelope = (try? storage.readJSON(
            ArmedInAppMessagesResponse.self,
            at: storage.armedInAppMessagesFile
        )) ?? nil {
            indexInApp(envelope.messages)
        }
    }

    func surveys(for eventName: String) -> [ArmedSurvey] {
        queue.sync { surveysByEvent[eventName] ?? [] }
    }

    func surveySnapshot() -> [ArmedSurvey] {
        queue.sync { allSurveys }
    }

    func survey(id: String) -> ArmedSurvey? {
        queue.sync { surveysById[id] }
    }

    func inApp(for eventName: String) -> [ArmedInAppMessage] {
        queue.sync { inAppByEvent[eventName] ?? [] }
    }

    func replace(_ response: ArmedSurveysResponse) {
        queue.sync {
            indexSurveys(response.surveys)
            do {
                try storage.writeJSON(response, to: storage.armedSurveysFile)
            } catch {
                logger.error("armed survey cache persist failed", error: error)
            }
        }
    }

    func replace(_ response: ArmedInAppMessagesResponse) {
        queue.sync {
            indexInApp(response.messages)
            do {
                try storage.writeJSON(response, to: storage.armedInAppMessagesFile)
            } catch {
                logger.error("armed in-app cache persist failed", error: error)
            }
        }
    }

    func clear() {
        queue.sync {
            surveysByEvent = [:]
            surveysById = [:]
            allSurveys = []
            inAppByEvent = [:]
            try? storage.deleteFile(at: storage.armedSurveysFile)
            try? storage.deleteFile(at: storage.armedInAppMessagesFile)
        }
    }

    private func indexSurveys(_ surveys: [ArmedSurvey]) {
        allSurveys = surveys
        surveysByEvent = Dictionary(grouping: surveys, by: \.eventName)
        surveysById = [:]
        for survey in surveys { surveysById[survey.campaignId] = survey }
    }

    private func indexInApp(_ messages: [ArmedInAppMessage]) {
        inAppByEvent = Dictionary(grouping: messages.filter { !$0.eventName.isEmpty }, by: \.eventName)
    }
}
