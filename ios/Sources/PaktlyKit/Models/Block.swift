import Foundation

// MARK: - Block (sum type)

/// One renderable unit inside a lesson. The schema's `oneOf` is modeled here as
/// a Swift enum tagged on the JSON `type` discriminator. The SDK's view layer
/// switches on this enum to render the appropriate UI.
public enum Block: Codable, Equatable, Sendable {
    case explanation(ExplanationBlock)
    case vocabulary(VocabularyBlock)
    case exercise(ExerciseBlock)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TypeKey.self)
        let type = try c.decode(String.self, forKey: .type)
        let single = try decoder.singleValueContainer()
        switch type {
        case "explanation":
            self = .explanation(try single.decode(ExplanationBlock.self))
        case "vocabulary":
            self = .vocabulary(try single.decode(VocabularyBlock.self))
        case "exercise":
            self = .exercise(try single.decode(ExerciseBlock.self))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "unknown block type \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .explanation(let b): try single.encode(b)
        case .vocabulary(let b): try single.encode(b)
        case .exercise(let b): try single.encode(b)
        }
    }

    private enum TypeKey: String, CodingKey { case type }
}

// MARK: - Explanation

public struct ExplanationBlock: Codable, Equatable, Sendable {
    public let type: String  // "explanation"
    public let text: String
    public let media: MediaRef?

    public init(text: String, media: MediaRef? = nil) {
        self.type = "explanation"
        self.text = text
        self.media = media
    }
}

// MARK: - Vocabulary

public struct VocabularyBlock: Codable, Equatable, Sendable {
    public let type: String  // "vocabulary"
    public let items: [VocabularyItem]

    public init(items: [VocabularyItem]) {
        self.type = "vocabulary"
        self.items = items
    }
}

public struct VocabularyItem: Codable, Equatable, Sendable {
    public let target: String
    public let translation: String
    public let transliteration: String?
    public let audio: String?
    public let image: String?
    public let notes: String?

    // Schema 1.1.0+
    public let ipa: String?
    public let examples: [VocabularyExample]

    public init(
        target: String,
        translation: String,
        transliteration: String? = nil,
        audio: String? = nil,
        image: String? = nil,
        notes: String? = nil,
        ipa: String? = nil,
        examples: [VocabularyExample] = []
    ) {
        self.target = target
        self.translation = translation
        self.transliteration = transliteration
        self.audio = audio
        self.image = image
        self.notes = notes
        self.ipa = ipa
        self.examples = examples
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.target = try c.decode(String.self, forKey: .target)
        self.translation = try c.decode(String.self, forKey: .translation)
        self.transliteration = try c.decodeIfPresent(String.self, forKey: .transliteration)
        self.audio = try c.decodeIfPresent(String.self, forKey: .audio)
        self.image = try c.decodeIfPresent(String.self, forKey: .image)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.ipa = try c.decodeIfPresent(String.self, forKey: .ipa)
        self.examples = try c.decodeIfPresent([VocabularyExample].self, forKey: .examples) ?? []
    }
}

public struct VocabularyExample: Codable, Equatable, Sendable {
    public let text: String
    public let translation: String
    public let audio: String?
    public let notes: String?

    public init(text: String, translation: String, audio: String? = nil, notes: String? = nil) {
        self.text = text
        self.translation = translation
        self.audio = audio
        self.notes = notes
    }
}

// MARK: - Exercise

public struct ExerciseBlock: Codable, Equatable, Sendable {
    public let type: String  // "exercise"
    public let exerciseType: ExerciseType
    public let prompt: String?
    /// Type-specific payload, decoded on demand into a typed exercise model
    /// (see `ExerciseData`). The schema intentionally leaves `data` open so
    /// new exercise types can ship without a manifest schema bump.
    public let data: AnyDecodable?

    public init(exerciseType: ExerciseType, prompt: String? = nil, data: AnyDecodable? = nil) {
        self.type = "exercise"
        self.exerciseType = exerciseType
        self.prompt = prompt
        self.data = data
    }
}

public enum ExerciseType: String, Codable, Sendable, CaseIterable {
    case flashcard
    case multipleChoice
    case typing
    case listening
    case matching
    case fillInBlank
}

// MARK: - MediaRef

public struct MediaRef: Codable, Equatable, Sendable {
    public let audio: String?
    public let image: String?
    public let video: String?

    public init(audio: String? = nil, image: String? = nil, video: String? = nil) {
        self.audio = audio
        self.image = image
        self.video = video
    }
}

// MARK: - AnyDecodable

/// A minimal Codable container that preserves arbitrary JSON. Used as a
/// pass-through for exercise-specific payloads so the data field can stay
/// open-ended in the schema while still round-tripping through Swift.
public struct AnyDecodable: Codable, Equatable, Sendable {
    public let value: AnyJSON

    public init(_ value: AnyJSON) { self.value = value }

    public init(from decoder: Decoder) throws {
        self.value = try AnyJSON(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

/// Recursive JSON value. Sendable because every leaf is a Sendable scalar
/// or an immutable composition of them.
public indirect enum AnyJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let arr = try? c.decode([AnyJSON].self) {
            self = .array(arr)
        } else if let obj = try? c.decode([String: AnyJSON].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}
