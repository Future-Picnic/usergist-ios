import Foundation

/// A multiple-choice option.
struct QuestionChoice: Codable, Equatable {
    let id: String
    let label: String
}

/// Four supported question types for v1 feedback prompts.
///
/// Uses a Codable enum-with-associated-values pattern backed by the
/// `type` discriminator field in the wire format.
enum Question: Codable, Equatable {
    case rating(Rating)
    case nps(Nps)
    case multipleChoice(MultipleChoice)
    case shortText(ShortText)

    struct Rating: Codable, Equatable {
        enum Display: String, Codable {
            case stars
            case numeric
            case emoji
        }

        let id: String
        let title: String
        let subtitle: String?
        let imageUrl: String?
        let scale: Int
        let display: Display?
        let lowLabel: String?
        let highLabel: String?
    }

    struct Nps: Codable, Equatable {
        let id: String
        let title: String
        let subtitle: String?
        let imageUrl: String?
        let followUp: String?
        let lowLabel: String?
        let highLabel: String?
    }

    struct MultipleChoice: Codable, Equatable {
        let id: String
        let title: String
        let subtitle: String?
        let imageUrl: String?
        let options: [QuestionChoice]
        let multiSelect: Bool?
    }

    struct ShortText: Codable, Equatable {
        let id: String
        let title: String
        let subtitle: String?
        let imageUrl: String?
        let placeholder: String?
        let maxLength: Int?
    }

    var id: String {
        switch self {
        case .rating(let q): return q.id
        case .nps(let q): return q.id
        case .multipleChoice(let q): return q.id
        case .shortText(let q): return q.id
        }
    }

    var title: String {
        switch self {
        case .rating(let q): return q.title
        case .nps(let q): return q.title
        case .multipleChoice(let q): return q.title
        case .shortText(let q): return q.title
        }
    }

    var subtitle: String? {
        switch self {
        case .rating(let q): return q.subtitle
        case .nps(let q): return q.subtitle
        case .multipleChoice(let q): return q.subtitle
        case .shortText(let q): return q.subtitle
        }
    }

    var imageUrl: String? {
        switch self {
        case .rating(let q): return q.imageUrl
        case .nps(let q): return q.imageUrl
        case .multipleChoice(let q): return q.imageUrl
        case .shortText(let q): return q.imageUrl
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum Kind: String, Codable {
        case rating
        case nps
        case multipleChoice = "multiple_choice"
        case shortText = "short_text"
    }

    init(from decoder: Decoder) throws {
        let kindContainer = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try kindContainer.decode(Kind.self, forKey: .type)
        let single = try decoder.singleValueContainer()
        switch kind {
        case .rating:
            self = .rating(try single.decode(Rating.self))
        case .nps:
            self = .nps(try single.decode(Nps.self))
        case .multipleChoice:
            self = .multipleChoice(try single.decode(MultipleChoice.self))
        case .shortText:
            self = .shortText(try single.decode(ShortText.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var kindContainer = encoder.container(keyedBy: CodingKeys.self)
        var single = encoder.singleValueContainer()
        switch self {
        case .rating(let q):
            try kindContainer.encode(Kind.rating, forKey: .type)
            try single.encode(q)
        case .nps(let q):
            try kindContainer.encode(Kind.nps, forKey: .type)
            try single.encode(q)
        case .multipleChoice(let q):
            try kindContainer.encode(Kind.multipleChoice, forKey: .type)
            try single.encode(q)
        case .shortText(let q):
            try kindContainer.encode(Kind.shortText, forKey: .type)
            try single.encode(q)
        }
    }
}
