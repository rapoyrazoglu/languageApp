import Foundation

/// Async REST client for any paktly-compatible registry.
///
/// The SDK is registry-agnostic: point this at `https://api.paktly.dev` or your
/// own self-hosted instance — same endpoints, same contracts. All methods are
/// async and throw `RegistryError`. Token state is managed by the actor so
/// callers can share a single instance across concurrent requests.
public actor RegistryClient {
    public let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var token: String?

    public init(baseURL: URL, session: URLSession = .shared, token: String? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
        self.decoder = Self.makeDecoder()
        self.encoder = Self.makeEncoder()
    }

    /// Set or clear the bearer token used for authenticated endpoints. The
    /// host app typically calls this after `login` / `register` returns, and
    /// again with `nil` on logout.
    public func setToken(_ token: String?) {
        self.token = token
    }

    public func currentToken() -> String? { token }

    // MARK: - Auth

    public func register(email: String, password: String, displayName: String? = nil) async throws -> TokenResponse {
        let body = RegisterRequest(email: email, password: password, displayName: displayName)
        let response: TokenResponse = try await send(
            method: "POST", path: "/v1/auth/register", body: body, authenticated: false
        )
        self.token = response.token
        return response
    }

    public func login(email: String, password: String) async throws -> TokenResponse {
        let body = LoginRequest(email: email, password: password)
        let response: TokenResponse = try await send(
            method: "POST", path: "/v1/auth/login", body: body, authenticated: false
        )
        self.token = response.token
        return response
    }

    public func me() async throws -> User {
        try await send(method: "GET", path: "/v1/auth/me", authenticated: true)
    }

    // MARK: - Packs

    public func listPacks(
        language: String? = nil,
        level: String? = nil,
        tag: String? = nil,
        q: String? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> PackPage {
        var query: [URLQueryItem] = []
        if let language { query.append(.init(name: "language", value: language)) }
        if let level { query.append(.init(name: "level", value: level)) }
        if let tag { query.append(.init(name: "tag", value: tag)) }
        if let q { query.append(.init(name: "q", value: q)) }
        if let limit { query.append(.init(name: "limit", value: String(limit))) }
        if let cursor { query.append(.init(name: "cursor", value: cursor)) }
        return try await send(method: "GET", path: "/v1/packs", query: query, authenticated: false)
    }

    public func getPack(id: String) async throws -> PackDetail {
        try await send(method: "GET", path: "/v1/packs/\(escape(id))", authenticated: false)
    }

    public func downloadInfo(packId: String, version: String) async throws -> DownloadInfo {
        try await send(
            method: "GET",
            path: "/v1/packs/\(escape(packId))/versions/\(escape(version))/download",
            authenticated: false
        )
    }

    // MARK: - Authoring (write side)

    /// Upload a pack ZIP directly. The caller has already produced the zip on
    /// disk or in memory; this just frames it as multipart/form-data and POSTs.
    /// Auth required — the JWT must be set via `login` / `register` / `setToken`
    /// first.
    public func uploadPack(zipData: Data, filename: String = "pack.zip") async throws -> IngestResult {
        let boundary = "PaktlyKit-\(UUID().uuidString)"
        let body = Self.multipartBody(
            boundary: boundary,
            field: "pack",
            filename: filename,
            mimeType: "application/zip",
            data: zipData
        )
        let request = try buildRequest(
            method: "POST",
            path: "/v1/packs/upload",
            query: [],
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            authenticated: true
        )
        return try await execute(request)
    }

    /// Ask the registry to fetch the latest GitHub release of a pack repo and
    /// ingest it. The backend resolves the asset, downloads, validates, stores.
    public func importGitHub(repoUrl: String) async throws -> IngestResult {
        struct Body: Encodable { let repoUrl: String }
        return try await send(
            method: "POST",
            path: "/v1/packs/import-github",
            body: Body(repoUrl: repoUrl),
            authenticated: true
        )
    }

    private static func multipartBody(
        boundary: String,
        field: String,
        filename: String,
        mimeType: String,
        data: Data
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(data)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }

    // MARK: - Internal request plumbing

    private func send<Body: Encodable, Out: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Body,
        authenticated: Bool
    ) async throws -> Out {
        let request = try buildRequest(
            method: method, path: path, query: query,
            body: try encoder.encode(body),
            contentType: "application/json",
            authenticated: authenticated
        )
        return try await execute(request)
    }

    private func send<Out: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        authenticated: Bool
    ) async throws -> Out {
        let request = try buildRequest(
            method: method, path: path, query: query,
            body: nil, contentType: nil, authenticated: authenticated
        )
        return try await execute(request)
    }

    private func buildRequest(
        method: String,
        path: String,
        query: [URLQueryItem],
        body: Data?,
        contentType: String?,
        authenticated: Bool
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw RegistryError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw RegistryError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        }
        if authenticated, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func execute<Out: Decodable>(_ request: URLRequest) async throws -> Out {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RegistryError.transport(error as any Error & Sendable)
        }
        guard let http = response as? HTTPURLResponse else {
            throw RegistryError.unexpectedResponse(status: -1, body: previewBody(data))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw mapError(status: http.statusCode, headers: http.allHeaderFields, data: data)
        }
        do {
            return try decoder.decode(Out.self, from: data)
        } catch {
            throw RegistryError.decoding(error as any Error & Sendable)
        }
    }

    private func mapError(status: Int, headers: [AnyHashable: Any], data: Data) -> RegistryError {
        let retryAfter = (headers["Retry-After"] as? String).flatMap(Int.init)
        if let envelope = try? decoder.decode(APIErrorBody.self, from: data) {
            return .http(
                status: status,
                code: envelope.error.code,
                message: envelope.error.message,
                fields: envelope.error.fields,
                retryAfter: retryAfter
            )
        }
        return .unexpectedResponse(status: status, body: previewBody(data))
    }

    private func previewBody(_ data: Data) -> String {
        String(data: data.prefix(512), encoding: .utf8) ?? "<\(data.count) bytes>"
    }

    private func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }

    // MARK: - JSON setup

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = Self.iso8601WithFraction.date(from: raw) { return date }
            if let date = Self.iso8601Plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "invalid ISO 8601 date: \(raw)"
            )
        }
        return d
    }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static let iso8601WithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
