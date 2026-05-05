import Foundation

/// A pack that has been downloaded and unpacked to disk. Lessons and media are
/// resolved from this root URL on demand — the manifest is the only file
/// loaded eagerly so callers can reason about pack metadata without paying
/// for every lesson's IO.
public struct InstalledPack: Sendable, Equatable {
    public let manifest: Manifest
    public let rootURL: URL
    public let installedAt: Date
    /// SHA256 of the original archive — preserved so callers can re-verify
    /// integrity without re-fetching.
    public let archiveSHA256: String
    public let archiveSizeBytes: Int64

    public var packId: String { manifest.id }
    public var version: String { manifest.version }

    /// Load a lesson by its manifest-declared id. Throws if the lesson is not
    /// declared in the manifest, the lesson JSON file is missing, or it fails
    /// to decode.
    public func lesson(id: String) throws -> Lesson {
        guard let ref = manifest.lessons.first(where: { $0.id == id }) else {
            throw PackStoreError.lessonNotFound(id: id)
        }
        let url = rootURL.appendingPathComponent(ref.file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PackStoreError.lessonFileMissing(file: ref.file)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PackStoreError.io(error as any Error & Sendable)
        }
        do {
            return try JSONDecoder().decode(Lesson.self, from: data)
        } catch {
            throw PackStoreError.manifestInvalid(error as any Error & Sendable)
        }
    }

    /// Resolve a media reference (e.g. `"media/audio/konnichiwa.mp3"`) to its
    /// on-disk URL. Returns nil if the referenced file doesn't exist on disk
    /// — callers can then fall back (e.g. AVSpeechSynthesizer).
    public func mediaURL(forRelativePath relativePath: String) -> URL? {
        let url = rootURL.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
