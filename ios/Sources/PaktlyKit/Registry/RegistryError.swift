import Foundation

/// Errors surfaced by `RegistryClient`. Transport / decoding failures wrap the
/// underlying `Error`; HTTP errors carry the structured envelope from the
/// backend so callers can switch on `code` for stable handling.
public enum RegistryError: Error, Sendable {
    case invalidURL
    case transport(any Error & Sendable)
    case decoding(any Error & Sendable)
    case http(status: Int, code: APIErrorCode, message: String, fields: [APIErrorField], retryAfter: Int?)
    /// HTTP non-2xx where the body did not decode as the standard error envelope.
    /// Surfaces enough to debug while keeping the type total.
    case unexpectedResponse(status: Int, body: String)
}

extension RegistryError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidURL:
            return "RegistryError.invalidURL"
        case .transport(let err):
            return "RegistryError.transport(\(err))"
        case .decoding(let err):
            return "RegistryError.decoding(\(err))"
        case .http(let status, let code, let message, let fields, let retryAfter):
            var s = "RegistryError.http(\(status), \(code.rawValue), \(message)"
            if !fields.isEmpty { s += ", fields=\(fields.count)" }
            if let r = retryAfter { s += ", retryAfter=\(r)" }
            return s + ")"
        case .unexpectedResponse(let status, let body):
            let preview = body.prefix(200)
            return "RegistryError.unexpectedResponse(\(status), \(preview))"
        }
    }
}
