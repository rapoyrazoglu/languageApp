import Foundation

// MARK: - Auth

public struct RegisterRequest: Codable, Sendable {
    public let email: String
    public let password: String
    public let displayName: String?

    public init(email: String, password: String, displayName: String? = nil) {
        self.email = email
        self.password = password
        self.displayName = displayName
    }
}

public struct LoginRequest: Codable, Sendable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct TokenResponse: Codable, Sendable {
    public let token: String
    public let expiresAt: Date
    public let user: User

    public init(token: String, expiresAt: Date, user: User) {
        self.token = token
        self.expiresAt = expiresAt
        self.user = user
    }
}

public struct User: Codable, Sendable, Equatable {
    public let id: String
    public let email: String
    public let displayName: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        email: String,
        displayName: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Pack registry

/// One pack as returned by the registry. This is the registry's *catalog* view —
/// flatter than the on-disk `Manifest` because it indexes denormalized fields
/// (e.g. `languageCode` instead of nested `language`) for search.
public struct Pack: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let description: String?
    public let languageCode: String
    public let languageName: String
    public let uiLanguage: String?
    public let level: String?
    public let authorName: String
    public let authorUrl: String?
    public let license: String
    public let homepage: String?
    public let repositoryUrl: String?
    public let tags: [String]
    public let latestVersion: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.languageCode = try c.decode(String.self, forKey: .languageCode)
        self.languageName = try c.decode(String.self, forKey: .languageName)
        self.uiLanguage = try c.decodeIfPresent(String.self, forKey: .uiLanguage)
        self.level = try c.decodeIfPresent(String.self, forKey: .level)
        self.authorName = try c.decode(String.self, forKey: .authorName)
        self.authorUrl = try c.decodeIfPresent(String.self, forKey: .authorUrl)
        self.license = try c.decode(String.self, forKey: .license)
        self.homepage = try c.decodeIfPresent(String.self, forKey: .homepage)
        self.repositoryUrl = try c.decodeIfPresent(String.self, forKey: .repositoryUrl)
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.latestVersion = try c.decodeIfPresent(String.self, forKey: .latestVersion)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public init(
        id: String,
        name: String,
        description: String? = nil,
        languageCode: String,
        languageName: String,
        uiLanguage: String? = nil,
        level: String? = nil,
        authorName: String,
        authorUrl: String? = nil,
        license: String,
        homepage: String? = nil,
        repositoryUrl: String? = nil,
        tags: [String] = [],
        latestVersion: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.languageCode = languageCode
        self.languageName = languageName
        self.uiLanguage = uiLanguage
        self.level = level
        self.authorName = authorName
        self.authorUrl = authorUrl
        self.license = license
        self.homepage = homepage
        self.repositoryUrl = repositoryUrl
        self.tags = tags
        self.latestVersion = latestVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PackVersion: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable { case github, upload }

    public let packId: String
    public let version: String
    public let schemaVersion: String
    public let sha256: String
    public let sizeBytes: Int64
    public let storageKey: String?
    public let source: Source
    public let sourceUrl: String?
    /// Cached manifest bytes the backend stored at ingest time. Decoded lazily
    /// because callers usually only need it after they've decided to download.
    public let manifest: AnyJSON?
    public let minSdkVersion: String?
    public let createdAt: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.packId = try c.decode(String.self, forKey: .packId)
        self.version = try c.decode(String.self, forKey: .version)
        self.schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        self.sha256 = try c.decode(String.self, forKey: .sha256)
        self.sizeBytes = try c.decode(Int64.self, forKey: .sizeBytes)
        self.storageKey = try c.decodeIfPresent(String.self, forKey: .storageKey)
        self.source = try c.decode(Source.self, forKey: .source)
        self.sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl)
        self.manifest = try c.decodeIfPresent(AnyJSON.self, forKey: .manifest)
        self.minSdkVersion = try c.decodeIfPresent(String.self, forKey: .minSdkVersion)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

public struct PackDetail: Codable, Sendable, Equatable {
    public let pack: Pack
    public let versions: [PackVersion]
}

public struct PackPage: Codable, Sendable, Equatable {
    public let packs: [Pack]
    public let nextCursor: String?
    public let limit: Int

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.packs = try c.decode([Pack].self, forKey: .packs)
        self.nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
        self.limit = try c.decode(Int.self, forKey: .limit)
    }
}

public struct DownloadInfo: Codable, Sendable, Equatable {
    public let url: URL
    public let sha256: String
    public let sizeBytes: Int64
    public let expiresIn: Int
}

public struct IngestResult: Codable, Sendable, Equatable {
    public let packId: String
    public let version: String
    public let storageKey: String?
    public let sha256: String
    public let sizeBytes: Int64
}

// MARK: - Error envelope

/// Stable error code returned by the backend. New codes may be added; clients
/// that don't recognise a code see `.unknown` and should fall back to the
/// human-readable message.
public enum APIErrorCode: String, Sendable, Equatable {
    case badRequest = "BAD_REQUEST"
    case invalidJSON = "INVALID_JSON"
    case missingField = "MISSING_FIELD"
    case unauthorized = "UNAUTHORIZED"
    case tokenExpired = "TOKEN_EXPIRED"
    case forbidden = "FORBIDDEN"
    case notFound = "NOT_FOUND"
    case conflict = "CONFLICT"
    case emailTaken = "EMAIL_TAKEN"
    case versionExists = "VERSION_EXISTS"
    case packOwnerMismatch = "PACK_OWNER_MISMATCH"
    case packValidationFailed = "PACK_VALIDATION_FAILED"
    case payloadTooLarge = "PAYLOAD_TOO_LARGE"
    case rateLimited = "RATE_LIMITED"
    case badGateway = "BAD_GATEWAY"
    case `internal` = "INTERNAL"
    case unknown
}

extension APIErrorCode: Decodable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = APIErrorCode(rawValue: raw) ?? .unknown
    }
}

public struct APIErrorField: Decodable, Sendable, Equatable {
    public let path: String
    public let message: String
}

public struct APIErrorBody: Decodable, Sendable, Equatable {
    public let error: APIErrorDetail
}

public struct APIErrorDetail: Decodable, Sendable, Equatable {
    public let code: APIErrorCode
    public let message: String
    public let fields: [APIErrorField]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try c.decode(APIErrorCode.self, forKey: .code)
        self.message = try c.decode(String.self, forKey: .message)
        self.fields = try c.decodeIfPresent([APIErrorField].self, forKey: .fields) ?? []
    }

    private enum CodingKeys: String, CodingKey { case code, message, fields }
}
