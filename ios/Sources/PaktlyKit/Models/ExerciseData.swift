import Foundation

// MARK: - Typed exercise payload

/// Typed view of an `ExerciseBlock.data` payload, one variant per mechanic
/// family. The outer `ExerciseType` enum disambiguates between a family's
/// types (e.g. `flashcard` vs `flashcardReverse` both produce
/// `.recall(FlashcardData)` — the type tells the renderer which side starts
/// face-up; the data shape is identical).
///
/// The schema deliberately keeps `data` open-ended (`type: object`) so we can
/// evolve payloads without a manifest schema bump for every minor tweak.
/// `ExerciseData` is the SDK-level contract: views consume it directly.
/// Forward-compat: an unknown future variant falls into `.raw(AnyJSON)` so
/// the runner can still surface metadata or a placeholder.
public enum ExerciseData: Sendable, Equatable {
    case recall(FlashcardData)
    case multipleChoice(MultipleChoiceData)
    case typing(TypingData)
    case listening(ListeningData)
    case matching(MatchingData)
    case fillInBlank(FillInBlankData)
    case wordOrder(WordOrderData)
    case reading(ReadingData)
    case production(ProductionData)
    case categorization(CategorizationData)
    case raw(AnyJSON)

    /// Decode the typed payload for a given exercise type from a raw
    /// `AnyDecodable` payload. Round-trips through JSON so each family struct
    /// gets the standard Codable behaviour without ad-hoc AnyJSON walkers.
    public static func parse(exerciseType: ExerciseType, raw: AnyDecodable?) throws -> ExerciseData? {
        guard let raw else { return nil }
        let json = try JSONEncoder().encode(raw.value)
        let decoder = JSONDecoder()
        switch exerciseType.family {
        case .recall:
            return .recall(try decoder.decode(FlashcardData.self, from: json))
        case .multipleChoice:
            return .multipleChoice(try decoder.decode(MultipleChoiceData.self, from: json))
        case .typing:
            return .typing(try decoder.decode(TypingData.self, from: json))
        case .listening:
            return .listening(try decoder.decode(ListeningData.self, from: json))
        case .matching:
            return .matching(try decoder.decode(MatchingData.self, from: json))
        case .fillInBlank:
            return .fillInBlank(try decoder.decode(FillInBlankData.self, from: json))
        case .wordOrder:
            return .wordOrder(try decoder.decode(WordOrderData.self, from: json))
        case .reading:
            return .reading(try decoder.decode(ReadingData.self, from: json))
        case .production:
            return .production(try decoder.decode(ProductionData.self, from: json))
        case .categorization:
            return .categorization(try decoder.decode(CategorizationData.self, from: json))
        }
    }
}

// MARK: - Shared media slot

/// One side of an exercise prompt. Any combination of fields may be present —
/// e.g. `multipleChoiceAudio` provides only `audio`; `multipleChoiceContext`
/// provides only `text` with `{{blank}}` markers; `multipleChoiceImage`
/// provides only `image`. Renderers prefer richer media when available.
public struct ExerciseMedia: Codable, Sendable, Equatable {
    public let text: String?
    public let audio: String?
    public let image: String?

    public init(text: String? = nil, audio: String? = nil, image: String? = nil) {
        self.text = text
        self.audio = audio
        self.image = image
    }
}

// MARK: - Family 1 — Recall (flashcard variants)

/// Two-faced card. `flashcard` shows `front` first and reveals `back`;
/// `flashcardReverse` flips the start side. `flashcardAudio` typically fills
/// the front's `audio`; `flashcardImage` typically fills the front's `image`.
public struct FlashcardData: Codable, Sendable, Equatable {
    public let front: ExerciseMedia
    public let back: ExerciseMedia
    public let hint: String?

    public init(front: ExerciseMedia, back: ExerciseMedia, hint: String? = nil) {
        self.front = front
        self.back = back
        self.hint = hint
    }
}

// MARK: - Family 2 — MultipleChoice

public struct MultipleChoiceData: Codable, Sendable, Equatable {
    public let prompt: ExerciseMedia
    public let options: [String]
    public let correctIndex: Int
    public let explanation: String?

    public init(prompt: ExerciseMedia, options: [String], correctIndex: Int, explanation: String? = nil) {
        self.prompt = prompt
        self.options = options
        self.correctIndex = correctIndex
        self.explanation = explanation
    }
}

// MARK: - Family 3 — Typing

public struct TypingData: Codable, Sendable, Equatable {
    public let prompt: ExerciseMedia
    public let answer: String
    public let acceptedAlternatives: [String]
    public let caseSensitive: Bool
    public let hint: String?

    public init(
        prompt: ExerciseMedia,
        answer: String,
        acceptedAlternatives: [String] = [],
        caseSensitive: Bool = false,
        hint: String? = nil
    ) {
        self.prompt = prompt
        self.answer = answer
        self.acceptedAlternatives = acceptedAlternatives
        self.caseSensitive = caseSensitive
        self.hint = hint
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.prompt = try c.decode(ExerciseMedia.self, forKey: .prompt)
        self.answer = try c.decode(String.self, forKey: .answer)
        self.acceptedAlternatives = try c.decodeIfPresent([String].self, forKey: .acceptedAlternatives) ?? []
        self.caseSensitive = try c.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
        self.hint = try c.decodeIfPresent(String.self, forKey: .hint)
    }
}

// MARK: - Family 4 — Listening

/// One struct, three variants distinguished by which fields are populated:
/// - `listening`: `audio` + `options` + `correctIndex` (replay-aware MC)
/// - `dictation`: `audio` + `answer` (full sentence to type)
/// - `listenAndAct`: `audio` + `imageOptions` + `correctIndex` (tap correct image)
public struct ListeningData: Codable, Sendable, Equatable {
    public let audio: String
    public let transcript: String?
    public let options: [String]?
    public let correctIndex: Int?
    public let answer: String?
    public let imageOptions: [String]?

    public init(
        audio: String,
        transcript: String? = nil,
        options: [String]? = nil,
        correctIndex: Int? = nil,
        answer: String? = nil,
        imageOptions: [String]? = nil
    ) {
        self.audio = audio
        self.transcript = transcript
        self.options = options
        self.correctIndex = correctIndex
        self.answer = answer
        self.imageOptions = imageOptions
    }
}

// MARK: - Family 5 — Matching

public struct MatchingPair: Codable, Sendable, Equatable {
    public let left: ExerciseMedia
    public let right: ExerciseMedia

    public init(left: ExerciseMedia, right: ExerciseMedia) {
        self.left = left
        self.right = right
    }
}

public struct MatchingData: Codable, Sendable, Equatable {
    public let pairs: [MatchingPair]

    public init(pairs: [MatchingPair]) { self.pairs = pairs }
}

// MARK: - Family 6 — FillInBlank

/// `template` carries blank markers in the literal form `{{1}}`, `{{2}}`, …
/// indexing into `answers`. `options` is used by `fillInBlankChoice` to give
/// the user a fixed pool of words; left nil means free-typing.
public struct FillInBlankData: Codable, Sendable, Equatable {
    public let template: String
    public let answers: [String]
    public let acceptedAlternatives: [[String]]
    public let options: [String]?
    public let caseSensitive: Bool

    public init(
        template: String,
        answers: [String],
        acceptedAlternatives: [[String]] = [],
        options: [String]? = nil,
        caseSensitive: Bool = false
    ) {
        self.template = template
        self.answers = answers
        self.acceptedAlternatives = acceptedAlternatives
        self.options = options
        self.caseSensitive = caseSensitive
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.template = try c.decode(String.self, forKey: .template)
        self.answers = try c.decode([String].self, forKey: .answers)
        self.acceptedAlternatives = try c.decodeIfPresent([[String]].self, forKey: .acceptedAlternatives) ?? []
        self.options = try c.decodeIfPresent([String].self, forKey: .options)
        self.caseSensitive = try c.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
    }
}

// MARK: - Family 7 — WordOrder

/// `correctOrder` indexes into `tiles`. For `letterScramble` `tiles` are
/// individual letters; for `wordOrder` they are words. Distractor tiles
/// (extra wrong tiles to make the puzzle harder) live in `distractors`.
public struct WordOrderData: Codable, Sendable, Equatable {
    public let tiles: [String]
    public let correctOrder: [Int]
    public let distractors: [String]
    public let translation: String?

    public init(
        tiles: [String],
        correctOrder: [Int],
        distractors: [String] = [],
        translation: String? = nil
    ) {
        self.tiles = tiles
        self.correctOrder = correctOrder
        self.distractors = distractors
        self.translation = translation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tiles = try c.decode([String].self, forKey: .tiles)
        self.correctOrder = try c.decode([Int].self, forKey: .correctOrder)
        self.distractors = try c.decodeIfPresent([String].self, forKey: .distractors) ?? []
        self.translation = try c.decodeIfPresent(String.self, forKey: .translation)
    }
}

// MARK: - Family 8 — Reading

public enum ReadingQuestionKind: String, Codable, Sendable {
    case trueFalse
    case multipleChoice
    case cloze
}

public struct ReadingQuestion: Codable, Sendable, Equatable {
    public let kind: ReadingQuestionKind
    public let prompt: String
    public let options: [String]?
    public let correctIndex: Int?
    public let truthy: Bool?
    public let answers: [String]?

    public init(
        kind: ReadingQuestionKind,
        prompt: String,
        options: [String]? = nil,
        correctIndex: Int? = nil,
        truthy: Bool? = nil,
        answers: [String]? = nil
    ) {
        self.kind = kind
        self.prompt = prompt
        self.options = options
        self.correctIndex = correctIndex
        self.truthy = truthy
        self.answers = answers
    }
}

public struct ReadingData: Codable, Sendable, Equatable {
    public let passage: String
    public let questions: [ReadingQuestion]
    public let glossary: [String: String]

    public init(passage: String, questions: [ReadingQuestion], glossary: [String: String] = [:]) {
        self.passage = passage
        self.questions = questions
        self.glossary = glossary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.passage = try c.decode(String.self, forKey: .passage)
        self.questions = try c.decode([ReadingQuestion].self, forKey: .questions)
        self.glossary = try c.decodeIfPresent([String: String].self, forKey: .glossary) ?? [:]
    }
}

// MARK: - Family 9 — Production

/// Free-form text production. `referenceAnswer` is a model answer the SDK can
/// reveal as a comparison; full grading is impractical without a server-side
/// LLM (Phase 8). `requiredWords` are tokens the answer must contain.
public struct ProductionData: Codable, Sendable, Equatable {
    public let prompt: ExerciseMedia
    public let referenceAnswer: String?
    public let requiredWords: [String]
    public let minLength: Int?
    public let maxLength: Int?

    public init(
        prompt: ExerciseMedia,
        referenceAnswer: String? = nil,
        requiredWords: [String] = [],
        minLength: Int? = nil,
        maxLength: Int? = nil
    ) {
        self.prompt = prompt
        self.referenceAnswer = referenceAnswer
        self.requiredWords = requiredWords
        self.minLength = minLength
        self.maxLength = maxLength
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.prompt = try c.decode(ExerciseMedia.self, forKey: .prompt)
        self.referenceAnswer = try c.decodeIfPresent(String.self, forKey: .referenceAnswer)
        self.requiredWords = try c.decodeIfPresent([String].self, forKey: .requiredWords) ?? []
        self.minLength = try c.decodeIfPresent(Int.self, forKey: .minLength)
        self.maxLength = try c.decodeIfPresent(Int.self, forKey: .maxLength)
    }
}

// MARK: - Family 10 — Categorization

public struct CategoryBucket: Codable, Sendable, Equatable {
    public let name: String
    public let items: [String]

    public init(name: String, items: [String]) {
        self.name = name
        self.items = items
    }
}

/// Two flavours:
/// - `oddOneOut`: `items` length 4 (or N), `oddIndex` marks the outlier.
///   `categories` is empty.
/// - `categorySort`: `items` is the unsorted pool, `categories` lists the
///   correct buckets each item belongs to. `oddIndex` is nil.
public struct CategorizationData: Codable, Sendable, Equatable {
    public let items: [String]
    public let oddIndex: Int?
    public let categories: [CategoryBucket]
    public let explanation: String?

    public init(
        items: [String],
        oddIndex: Int? = nil,
        categories: [CategoryBucket] = [],
        explanation: String? = nil
    ) {
        self.items = items
        self.oddIndex = oddIndex
        self.categories = categories
        self.explanation = explanation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try c.decode([String].self, forKey: .items)
        self.oddIndex = try c.decodeIfPresent(Int.self, forKey: .oddIndex)
        self.categories = try c.decodeIfPresent([CategoryBucket].self, forKey: .categories) ?? []
        self.explanation = try c.decodeIfPresent(String.self, forKey: .explanation)
    }
}

// MARK: - ExerciseBlock bridge

extension ExerciseBlock {
    /// Decode `data` into the typed family payload. Throws if the payload's
    /// shape doesn't match the family declared by `exerciseType` — that's a
    /// pack authoring error and the runner should surface it loudly.
    public func parseData() throws -> ExerciseData? {
        try ExerciseData.parse(exerciseType: exerciseType, raw: data)
    }
}
