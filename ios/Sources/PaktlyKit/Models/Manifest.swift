import Foundation

// MARK: - Manifest

/// Top-level descriptor of a pack, mirrored 1:1 with `manifest.json`.
///
/// Backwards-compatible across pack format `1.0.0` and `1.1.0`. Fields
/// introduced in 1.1.0 are optional; absent values decode as `nil`.
public struct Manifest: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let id: String
    public let name: String
    public let version: String
    public let description: String?
    public let language: Language
    public let uiLanguage: String?
    public let level: Level?
    public let author: Author
    public let license: String
    public let homepage: URL?
    public let repository: Repository?
    public let tags: [String]
    public let lessons: [LessonRef]
    public let dependencies: [Dependency]
    public let minSdkVersion: String?

    // Schema 1.1.0+
    public let aiCapabilities: AICapabilities?
    public let previousPack: String?
    public let nextPack: String?

    public init(
        schemaVersion: String,
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        language: Language,
        uiLanguage: String? = nil,
        level: Level? = nil,
        author: Author,
        license: String,
        homepage: URL? = nil,
        repository: Repository? = nil,
        tags: [String] = [],
        lessons: [LessonRef],
        dependencies: [Dependency] = [],
        minSdkVersion: String? = nil,
        aiCapabilities: AICapabilities? = nil,
        previousPack: String? = nil,
        nextPack: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.language = language
        self.uiLanguage = uiLanguage
        self.level = level
        self.author = author
        self.license = license
        self.homepage = homepage
        self.repository = repository
        self.tags = tags
        self.lessons = lessons
        self.dependencies = dependencies
        self.minSdkVersion = minSdkVersion
        self.aiCapabilities = aiCapabilities
        self.previousPack = previousPack
        self.nextPack = nextPack
    }

    // Manual decode so missing `tags` / `dependencies` decode as empty arrays
    // rather than failing — they're omitempty in the schema.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.version = try c.decode(String.self, forKey: .version)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.language = try c.decode(Language.self, forKey: .language)
        self.uiLanguage = try c.decodeIfPresent(String.self, forKey: .uiLanguage)
        self.level = try c.decodeIfPresent(Level.self, forKey: .level)
        self.author = try c.decode(Author.self, forKey: .author)
        self.license = try c.decode(String.self, forKey: .license)
        self.homepage = try c.decodeIfPresent(URL.self, forKey: .homepage)
        self.repository = try c.decodeIfPresent(Repository.self, forKey: .repository)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.lessons = try c.decode([LessonRef].self, forKey: .lessons)
        self.dependencies = try c.decodeIfPresent([Dependency].self, forKey: .dependencies) ?? []
        self.minSdkVersion = try c.decodeIfPresent(String.self, forKey: .minSdkVersion)
        self.aiCapabilities = try c.decodeIfPresent(AICapabilities.self, forKey: .aiCapabilities)
        self.previousPack = try c.decodeIfPresent(String.self, forKey: .previousPack)
        self.nextPack = try c.decodeIfPresent(String.self, forKey: .nextPack)
    }
}

// MARK: - Language

public struct Language: Codable, Equatable, Sendable {
    public let code: String
    public let name: String
    public let nativeName: String?
    public let script: String?
    public let direction: Direction?

    public enum Direction: String, Codable, Sendable {
        case ltr, rtl
    }

    public init(code: String, name: String, nativeName: String? = nil, script: String? = nil, direction: Direction? = nil) {
        self.code = code
        self.name = name
        self.nativeName = nativeName
        self.script = script
        self.direction = direction
    }
}

// MARK: - Level

public enum Level: String, Codable, Sendable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"
    case c2 = "C2"
    case mixed
}

// MARK: - Author / Repository / LessonRef / Dependency

public struct Author: Codable, Equatable, Sendable {
    public let name: String
    public let url: URL?
    public let email: String?

    public init(name: String, url: URL? = nil, email: String? = nil) {
        self.name = name
        self.url = url
        self.email = email
    }
}

public struct Repository: Codable, Equatable, Sendable {
    public let type: String
    public let url: URL

    public init(type: String, url: URL) {
        self.type = type
        self.url = url
    }
}

public struct LessonRef: Codable, Equatable, Sendable {
    public let id: String
    public let file: String
    public let title: String?
    public let order: Int?

    public init(id: String, file: String, title: String? = nil, order: Int? = nil) {
        self.id = id
        self.file = file
        self.title = title
        self.order = order
    }
}

public struct Dependency: Codable, Equatable, Sendable {
    public let id: String
    public let version: String

    public init(id: String, version: String) {
        self.id = id
        self.version = version
    }
}

// MARK: - AICapabilities (schema 1.1.0+)

/// Pack's declaration of which AI affordances it expects to support. Used by
/// the host app to decide which AI buttons to surface; the backend additionally
/// gates the actual AI call by the user's subscription tier. The pack itself
/// always works fully offline; AI is layered on top.
public struct AICapabilities: Codable, Equatable, Sendable {
    public let questionGeneration: Bool?
    public let explanation: Bool?
    public let conversation: Bool?
    public let hint: Bool?

    public init(
        questionGeneration: Bool? = nil,
        explanation: Bool? = nil,
        conversation: Bool? = nil,
        hint: Bool? = nil
    ) {
        self.questionGeneration = questionGeneration
        self.explanation = explanation
        self.conversation = conversation
        self.hint = hint
    }

    /// `true` when at least one capability is explicitly enabled. Convenient
    /// for the SDK to decide whether to surface any AI affordance at all.
    public var hasAnyEnabled: Bool {
        (questionGeneration ?? false)
            || (explanation ?? false)
            || (conversation ?? false)
            || (hint ?? false)
    }
}
