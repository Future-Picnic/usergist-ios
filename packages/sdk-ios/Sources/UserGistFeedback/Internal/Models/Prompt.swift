import Foundation

/// Lightweight prompt representation shipped to the SDK.
struct ClientPrompt: Codable, Equatable {
    let id: String
    let questions: [Question]
    let theme: PromptTheme?
}

/// Frequency-cap window configuration attached to armed triggers.
struct FrequencyCaps: Codable, Equatable {
    let perPromptDays: Int?
    let perUserDays: Int?
}
