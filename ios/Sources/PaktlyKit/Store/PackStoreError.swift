import Foundation

/// Errors surfaced by `PackStore`. Wrap rather than swallow underlying causes
/// so callers can present a useful message and log the root.
public enum PackStoreError: Error, Sendable {
    case checksumMismatch(expected: String, actual: String)
    case manifestMissing
    case manifestInvalid(any Error & Sendable)
    case lessonNotFound(id: String)
    case lessonFileMissing(file: String)
    case zipFailed(any Error & Sendable)
    case downloadFailed(any Error & Sendable)
    case io(any Error & Sendable)
}

extension PackStoreError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .checksumMismatch(let expected, let actual):
            return "PackStoreError.checksumMismatch(expected=\(expected), actual=\(actual))"
        case .manifestMissing:
            return "PackStoreError.manifestMissing"
        case .manifestInvalid(let err):
            return "PackStoreError.manifestInvalid(\(err))"
        case .lessonNotFound(let id):
            return "PackStoreError.lessonNotFound(\(id))"
        case .lessonFileMissing(let file):
            return "PackStoreError.lessonFileMissing(\(file))"
        case .zipFailed(let err):
            return "PackStoreError.zipFailed(\(err))"
        case .downloadFailed(let err):
            return "PackStoreError.downloadFailed(\(err))"
        case .io(let err):
            return "PackStoreError.io(\(err))"
        }
    }
}
