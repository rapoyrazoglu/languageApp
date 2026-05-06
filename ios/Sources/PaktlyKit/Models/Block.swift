import Foundation

// MARK: - Block (sum type)

/// One renderable unit inside a lesson. The schema's `oneOf` is modeled here as
/// a Swift enum tagged on the JSON `type` discriminator. The SDK's view layer
/// switches on this enum to render the appropriate UI.
///
/// Cases added in 1.2.0: `dialogue`, `kanji`, `grammar`. Existing 1.0.0 / 1.1.0
/// packs only emit `explanation`, `vocabulary`, `exercise` and decode as before.
public enum Block: Codable, Equatable, Sendable {
    case explanation(ExplanationBlock)
    case vocabulary(VocabularyBlock)
    case exercise(ExerciseBlock)
    case dialogue(DialogueBlock)
    case kanji(KanjiBlock)
    case grammar(GrammarBlock)

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
        case "dialogue":
            self = .dialogue(try single.decode(DialogueBlock.self))
        case "kanji":
            self = .kanji(try single.decode(KanjiBlock.self))
        case "grammar":
            self = .grammar(try single.decode(GrammarBlock.self))
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
        case .dialogue(let b): try single.encode(b)
        case .kanji(let b): try single.encode(b)
        case .grammar(let b): try single.encode(b)
        }
    }

    private enum TypeKey: String, CodingKey { case type }
}

// MARK: - Locale resolution (schema 1.2.0+ multi-locale fields)

/// Picks the best-matching string from a multi-locale translations map, with
/// graceful fallback to a legacy single-locale field.
///
/// Resolution order:
///   1. Exact match for `preferredLocale` (e.g. `"zh-Hans"`)
///   2. Progressive shortenings of `preferredLocale` (`"zh-Hans-CN"` → `"zh-Hans"` → `"zh"`)
///   3. Exact match for `uiLanguageFallback` (the pack's `manifest.uiLanguage`)
///   4. Progressive shortenings of `uiLanguageFallback`
///   5. The legacy single-locale `translation` value (1.0.0 / 1.1.0 packs)
///
/// Returns `nil` only when neither a translations map nor a legacy field is
/// available. The schema's `anyOf` enforces that at least one of them is
/// present, so a valid 1.2.0 pack will always produce a string here.
public enum LocaleResolver {
    public static func resolve(
        translations: [String: String]?,
        legacy: String?,
        preferredLocale: String? = nil,
        uiLanguageFallback: String? = nil
    ) -> String? {
        if let map = translations, !map.isEmpty {
            for candidate in [preferredLocale, uiLanguageFallback].compactMap({ $0 }) {
                for tag in fallbackChain(for: candidate) {
                    if let v = map[tag] { return v }
                }
            }
            // Last resort within the map: any single value, deterministically by key.
            if let firstKey = map.keys.sorted().first { return map[firstKey] }
        }
        return legacy
    }

    /// Splits a BCP-47 tag into its progressively shorter prefixes.
    /// `"zh-Hans-CN"` → `["zh-Hans-CN", "zh-Hans", "zh"]`.
    static func fallbackChain(for tag: String) -> [String] {
        let parts = tag.split(separator: "-")
        guard !parts.isEmpty else { return [] }
        var chain: [String] = []
        for end in stride(from: parts.count, through: 1, by: -1) {
            chain.append(parts.prefix(end).joined(separator: "-"))
        }
        return chain
    }
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
    /// Legacy single-locale translation (1.0.0+). May be `nil` on 1.2.0 packs
    /// that only emit `translations`. Use `resolvedTranslation(...)` to get a
    /// rendering-ready string.
    public let translation: String?
    /// Schema 1.2.0+. Multi-locale translation map keyed by BCP-47 tag.
    public let translations: [String: String]?
    public let transliteration: String?
    public let audio: String?
    public let image: String?
    public let notes: String?

    // Schema 1.1.0+
    public let ipa: String?
    public let examples: [VocabularyExample]

    public init(
        target: String,
        translation: String? = nil,
        translations: [String: String]? = nil,
        transliteration: String? = nil,
        audio: String? = nil,
        image: String? = nil,
        notes: String? = nil,
        ipa: String? = nil,
        examples: [VocabularyExample] = []
    ) {
        self.target = target
        self.translation = translation
        self.translations = translations
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
        self.translation = try c.decodeIfPresent(String.self, forKey: .translation)
        self.translations = try c.decodeIfPresent([String: String].self, forKey: .translations)
        self.transliteration = try c.decodeIfPresent(String.self, forKey: .transliteration)
        self.audio = try c.decodeIfPresent(String.self, forKey: .audio)
        self.image = try c.decodeIfPresent(String.self, forKey: .image)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.ipa = try c.decodeIfPresent(String.self, forKey: .ipa)
        self.examples = try c.decodeIfPresent([VocabularyExample].self, forKey: .examples) ?? []
    }

    /// Best-fit translation for the given locale chain. Falls back through
    /// `translations` map, then to legacy `translation`.
    public func resolvedTranslation(
        preferredLocale: String? = Locale.preferredLanguages.first,
        uiLanguageFallback: String? = nil
    ) -> String? {
        LocaleResolver.resolve(
            translations: translations,
            legacy: translation,
            preferredLocale: preferredLocale,
            uiLanguageFallback: uiLanguageFallback
        )
    }
}

public struct VocabularyExample: Codable, Equatable, Sendable {
    public let text: String
    public let translation: String?
    public let translations: [String: String]?
    public let audio: String?
    public let notes: String?

    public init(
        text: String,
        translation: String? = nil,
        translations: [String: String]? = nil,
        audio: String? = nil,
        notes: String? = nil
    ) {
        self.text = text
        self.translation = translation
        self.translations = translations
        self.audio = audio
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try c.decode(String.self, forKey: .text)
        self.translation = try c.decodeIfPresent(String.self, forKey: .translation)
        self.translations = try c.decodeIfPresent([String: String].self, forKey: .translations)
        self.audio = try c.decodeIfPresent(String.self, forKey: .audio)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    public func resolvedTranslation(
        preferredLocale: String? = Locale.preferredLanguages.first,
        uiLanguageFallback: String? = nil
    ) -> String? {
        LocaleResolver.resolve(
            translations: translations,
            legacy: translation,
            preferredLocale: preferredLocale,
            uiLanguageFallback: uiLanguageFallback
        )
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

    /// Schema 1.2.0+. Optional skill tags this exercise tests, e.g.
    /// `["vocab.n5", "grammar.particle.wa"]`. Reserved for future SRS /
    /// diagnostic features (Phase 6+); SDK currently passes through.
    public let skills: [String]?
    /// Schema 1.2.0+. Optional per-option diagnostic labels aligned by index
    /// with the exercise's choice list. `nil` entries indicate no diagnosis
    /// for that index.
    public let distractorTags: [String?]?

    public init(
        exerciseType: ExerciseType,
        prompt: String? = nil,
        data: AnyDecodable? = nil,
        skills: [String]? = nil,
        distractorTags: [String?]? = nil
    ) {
        self.type = "exercise"
        self.exerciseType = exerciseType
        self.prompt = prompt
        self.data = data
        self.skills = skills
        self.distractorTags = distractorTags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decode(String.self, forKey: .type)
        self.exerciseType = try c.decode(ExerciseType.self, forKey: .exerciseType)
        self.prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        self.data = try c.decodeIfPresent(AnyDecodable.self, forKey: .data)
        self.skills = try c.decodeIfPresent([String].self, forKey: .skills)
        self.distractorTags = try c.decodeIfPresent([String?].self, forKey: .distractorTags)
    }
}

/// All 30 exercise types creators can declare in a pack. Grouped into 10
/// mechanic families on the rendering side: a single SwiftUI view per family
/// handles every variant in that family by switching on this enum and on the
/// typed payload (`ExerciseData`).
///
/// The original 6 (introduced in pack format 1.1.0) are first; the 24 added
/// in 1.2.0 follow. Existing packs keep validating against the new schema —
/// we only added enum cases.
public enum ExerciseType: String, Codable, Sendable, CaseIterable {
    // Family 1 — Recall
    case flashcard
    case flashcardReverse
    case flashcardAudio
    case flashcardImage

    // Family 2 — MultipleChoice
    case multipleChoice
    case multipleChoiceReverse
    case multipleChoiceAudio
    case multipleChoiceImage
    case multipleChoiceContext

    // Family 3 — Typing
    case typing
    case typingReverse
    case typingAudio

    // Family 4 — Listening
    case listening
    case dictation
    case listenAndAct

    // Family 5 — Matching
    case matching
    case matchingAudio
    case matchingImage

    // Family 6 — FillInBlank
    case fillInBlank
    case fillInBlankChoice
    case fillInMultiple

    // Family 7 — WordOrder
    case wordOrder
    case letterScramble

    // Family 8 — Reading
    case readingTrueFalse
    case readingComprehension
    case readingCloze

    // Family 9 — Production
    case translateSentence
    case composeSentence

    // Family 10 — Categorization
    case oddOneOut
    case categorySort

    /// The mechanic family this type belongs to. Lets the runner pick the
    /// right view + typed `ExerciseData` decoder without a 30-arm switch
    /// at every call site.
    public var family: ExerciseFamily {
        switch self {
        case .flashcard, .flashcardReverse, .flashcardAudio, .flashcardImage:
            return .recall
        case .multipleChoice, .multipleChoiceReverse, .multipleChoiceAudio, .multipleChoiceImage, .multipleChoiceContext:
            return .multipleChoice
        case .typing, .typingReverse, .typingAudio:
            return .typing
        case .listening, .dictation, .listenAndAct:
            return .listening
        case .matching, .matchingAudio, .matchingImage:
            return .matching
        case .fillInBlank, .fillInBlankChoice, .fillInMultiple:
            return .fillInBlank
        case .wordOrder, .letterScramble:
            return .wordOrder
        case .readingTrueFalse, .readingComprehension, .readingCloze:
            return .reading
        case .translateSentence, .composeSentence:
            return .production
        case .oddOneOut, .categorySort:
            return .categorization
        }
    }
}

public enum ExerciseFamily: String, Sendable, CaseIterable {
    case recall
    case multipleChoice
    case typing
    case listening
    case matching
    case fillInBlank
    case wordOrder
    case reading
    case production
    case categorization
}

// MARK: - Dialogue (schema 1.2.0+)

public struct DialogueBlock: Codable, Equatable, Sendable {
    public let type: String  // "dialogue"
    public let context: String?
    public let contexts: [String: String]?
    public let lines: [DialogueLine]

    public init(
        context: String? = nil,
        contexts: [String: String]? = nil,
        lines: [DialogueLine]
    ) {
        self.type = "dialogue"
        self.context = context
        self.contexts = contexts
        self.lines = lines
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decode(String.self, forKey: .type)
        self.context = try c.decodeIfPresent(String.self, forKey: .context)
        self.contexts = try c.decodeIfPresent([String: String].self, forKey: .contexts)
        self.lines = try c.decode([DialogueLine].self, forKey: .lines)
    }

    public func resolvedContext(
        preferredLocale: String? = Locale.preferredLanguages.first,
        uiLanguageFallback: String? = nil
    ) -> String? {
        LocaleResolver.resolve(
            translations: contexts,
            legacy: context,
            preferredLocale: preferredLocale,
            uiLanguageFallback: uiLanguageFallback
        )
    }
}

public struct DialogueLine: Codable, Equatable, Sendable {
    public let speaker: String?
    public let target: String
    public let translation: String?
    public let translations: [String: String]?
    public let audio: String?
    public let notes: String?

    public init(
        speaker: String? = nil,
        target: String,
        translation: String? = nil,
        translations: [String: String]? = nil,
        audio: String? = nil,
        notes: String? = nil
    ) {
        self.speaker = speaker
        self.target = target
        self.translation = translation
        self.translations = translations
        self.audio = audio
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.speaker = try c.decodeIfPresent(String.self, forKey: .speaker)
        self.target = try c.decode(String.self, forKey: .target)
        self.translation = try c.decodeIfPresent(String.self, forKey: .translation)
        self.translations = try c.decodeIfPresent([String: String].self, forKey: .translations)
        self.audio = try c.decodeIfPresent(String.self, forKey: .audio)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    public func resolvedTranslation(
        preferredLocale: String? = Locale.preferredLanguages.first,
        uiLanguageFallback: String? = nil
    ) -> String? {
        LocaleResolver.resolve(
            translations: translations,
            legacy: translation,
            preferredLocale: preferredLocale,
            uiLanguageFallback: uiLanguageFallback
        )
    }
}

// MARK: - Kanji (schema 1.2.0+)

public struct KanjiBlock: Codable, Equatable, Sendable {
    public let type: String  // "kanji"
    public let items: [KanjiItem]

    public init(items: [KanjiItem]) {
        self.type = "kanji"
        self.items = items
    }
}

public struct KanjiItem: Codable, Equatable, Sendable {
    public let character: String
    public let meaning: String?
    public let meanings: [String: String]?
    public let onyomi: [String]
    public let kunyomi: [String]
    public let strokes: Int?
    public let jlptLevel: String?
    public let radicals: [String]
    public let mnemonic: String?
    public let mnemonics: [String: String]?
    public let audio: String?
    public let examples: [KanjiExample]

    public init(
        character: String,
        meaning: String? = nil,
        meanings: [String: String]? = nil,
        onyomi: [String] = [],
        kunyomi: [String] = [],
        strokes: Int? = nil,
        jlptLevel: String? = nil,
        radicals: [String] = [],
        mnemonic: String? = nil,
        mnemonics: [String: String]? = nil,
        audio: String? = nil,
        examples: [KanjiExample] = []
    ) {
        self.character = character
        self.meaning = meaning
        self.meanings = meanings
        self.onyomi = onyomi
        self.kunyomi = kunyomi
        self.strokes = strokes
        self.jlptLevel = jlptLevel
        self.radicals = radicals
        self.mnemonic = mnemonic
        self.mnemonics = mnemonics
        self.audio = audio
        self.examples = examples
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.character = try c.decode(String.self, forKey: .character)
        self.meaning = try c.decodeIfPresent(String.self, forKey: .meaning)
        self.meanings = try c.decodeIfPresent([String: String].self, forKey: .meanings)
        self.onyomi = try c.decodeIfPresent([String].self, forKey: .onyomi) ?? []
        self.kunyomi = try c.decodeIfPresent([String].self, forKey: .kunyomi) ?? []
        self.strokes = try c.decodeIfPresent(Int.self, forKey: .strokes)
        self.jlptLevel = try c.decodeIfPresent(String.self, forKey: .jlptLevel)
        self.radicals = try c.decodeIfPresent([String].self, forKey: .radicals) ?? []
        self.mnemonic = try c.decodeIfPresent(String.self, forKey: .mnemonic)
        self.mnemonics = try c.decodeIfPresent([String: String].self, forKey: .mnemonics)
        self.audio = try c.decodeIfPresent(String.self, forKey: .audio)
        self.examples = try c.decodeIfPresent([KanjiExample].self, forKey: .examples) ?? []
    }

    public func resolvedMeaning(
        preferredLocale: String? = Locale.preferredLanguages.first,
        uiLanguageFallback: String? = nil
    ) -> String? {
        LocaleResolver.resolve(
            translations: meanings,
            legacy: meaning,
            preferredLocale: preferredLocale,
            uiLanguageFallback: uiLanguageFallback
        )
    }

    public func resolvedMnemonic(
        preferredLocale: String? = Locale.preferredLanguages.first,
        uiLanguageFallback: String? = nil
    ) -> String? {
        LocaleResolver.resolve(
            translations: mnemonics,
            legacy: mnemonic,
            preferredLocale: preferredLocale,
            uiLanguageFallback: uiLanguageFallback
        )
    }
}

public struct KanjiExample: Codable, Equatable, Sendable {
    public let word: String
    public let reading: String?
    public let translation: String?
    public let translations: [String: String]?
    public let audio: String?

    public init(
        word: String,
        reading: String? = nil,
        translation: String? = nil,
        translations: [String: String]? = nil,
        audio: String? = nil
    ) {
        self.word = word
        self.reading = reading
        self.translation = translation
        self.translations = translations
        self.audio = audio
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.word = try c.decode(String.self, forKey: .word)
        self.reading = try c.decodeIfPresent(String.self, forKey: .reading)
        self.translation = try c.decodeIfPresent(String.self, forKey: .translation)
        self.translations = try c.decodeIfPresent([String: String].self, forKey: .translations)
        self.audio = try c.decodeIfPresent(String.self, forKey: .audio)
    }

    public func resolvedTranslation(
        preferredLocale: String? = Locale.preferredLanguages.first,
        uiLanguageFallback: String? = nil
    ) -> String? {
        LocaleResolver.resolve(
            translations: translations,
            legacy: translation,
            preferredLocale: preferredLocale,
            uiLanguageFallback: uiLanguageFallback
        )
    }
}

// MARK: - Grammar (schema 1.2.0+)

public struct GrammarBlock: Codable, Equatable, Sendable {
    public let type: String  // "grammar"
    public let pattern: String
    public let level: String?
    public let meaning: String?
    public let meanings: [String: String]?
    public let formation: String?
    public let formations: [String: String]?
    public let usage: String?
    public let usages: [String: String]?
    public let watchOut: String?
    public let watchOuts: [String: String]?
    public let examples: [VocabularyExample]
    public let related: [String]
    public let audio: String?

    public init(
        pattern: String,
        level: String? = nil,
        meaning: String? = nil,
        meanings: [String: String]? = nil,
        formation: String? = nil,
        formations: [String: String]? = nil,
        usage: String? = nil,
        usages: [String: String]? = nil,
        watchOut: String? = nil,
        watchOuts: [String: String]? = nil,
        examples: [VocabularyExample] = [],
        related: [String] = [],
        audio: String? = nil
    ) {
        self.type = "grammar"
        self.pattern = pattern
        self.level = level
        self.meaning = meaning
        self.meanings = meanings
        self.formation = formation
        self.formations = formations
        self.usage = usage
        self.usages = usages
        self.watchOut = watchOut
        self.watchOuts = watchOuts
        self.examples = examples
        self.related = related
        self.audio = audio
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decode(String.self, forKey: .type)
        self.pattern = try c.decode(String.self, forKey: .pattern)
        self.level = try c.decodeIfPresent(String.self, forKey: .level)
        self.meaning = try c.decodeIfPresent(String.self, forKey: .meaning)
        self.meanings = try c.decodeIfPresent([String: String].self, forKey: .meanings)
        self.formation = try c.decodeIfPresent(String.self, forKey: .formation)
        self.formations = try c.decodeIfPresent([String: String].self, forKey: .formations)
        self.usage = try c.decodeIfPresent(String.self, forKey: .usage)
        self.usages = try c.decodeIfPresent([String: String].self, forKey: .usages)
        self.watchOut = try c.decodeIfPresent(String.self, forKey: .watchOut)
        self.watchOuts = try c.decodeIfPresent([String: String].self, forKey: .watchOuts)
        self.examples = try c.decodeIfPresent([VocabularyExample].self, forKey: .examples) ?? []
        self.related = try c.decodeIfPresent([String].self, forKey: .related) ?? []
        self.audio = try c.decodeIfPresent(String.self, forKey: .audio)
    }

    public func resolvedMeaning(preferredLocale: String? = Locale.preferredLanguages.first, uiLanguageFallback: String? = nil) -> String? {
        LocaleResolver.resolve(translations: meanings, legacy: meaning, preferredLocale: preferredLocale, uiLanguageFallback: uiLanguageFallback)
    }

    public func resolvedFormation(preferredLocale: String? = Locale.preferredLanguages.first, uiLanguageFallback: String? = nil) -> String? {
        LocaleResolver.resolve(translations: formations, legacy: formation, preferredLocale: preferredLocale, uiLanguageFallback: uiLanguageFallback)
    }

    public func resolvedUsage(preferredLocale: String? = Locale.preferredLanguages.first, uiLanguageFallback: String? = nil) -> String? {
        LocaleResolver.resolve(translations: usages, legacy: usage, preferredLocale: preferredLocale, uiLanguageFallback: uiLanguageFallback)
    }

    public func resolvedWatchOut(preferredLocale: String? = Locale.preferredLanguages.first, uiLanguageFallback: String? = nil) -> String? {
        LocaleResolver.resolve(translations: watchOuts, legacy: watchOut, preferredLocale: preferredLocale, uiLanguageFallback: uiLanguageFallback)
    }
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
