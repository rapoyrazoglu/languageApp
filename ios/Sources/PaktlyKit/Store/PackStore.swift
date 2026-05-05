import Foundation
import CryptoKit

/// On-device cache of downloaded packs. The store owns a directory under
/// Application Support and keeps every installed pack at
/// `<root>/<packId>/<version>/`. Multiple versions of the same pack can
/// coexist; callers ask for the version they need.
///
/// All mutating operations go through the actor so two concurrent
/// `download` calls for the same (id, version) are serialized; the second
/// finds the first one's result and skips redundant work.
public actor PackStore {
    public let rootDirectory: URL
    private let fileManager: FileManager
    private let session: URLSession

    /// Default store rooted under `Application Support/PaktlyKit/packs`.
    public static let `default`: PackStore = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let root = support.appendingPathComponent("PaktlyKit/packs", isDirectory: true)
        return PackStore(rootDirectory: root)
    }()

    public init(rootDirectory: URL, fileManager: FileManager = .default, session: URLSession = .shared) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.session = session
    }

    // MARK: - Listing

    public func installedPacks() throws -> [InstalledPack] {
        try ensureRoot()
        var result: [InstalledPack] = []
        guard let packDirs = try? fileManager.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        for packDir in packDirs where packDir.hasDirectoryPath {
            let versions = (try? fileManager.contentsOfDirectory(at: packDir, includingPropertiesForKeys: nil)) ?? []
            for versionDir in versions where versionDir.hasDirectoryPath {
                if let pack = try? loadInstalled(at: versionDir) {
                    result.append(pack)
                }
            }
        }
        return result.sorted { ($0.packId, $0.version) < ($1.packId, $1.version) }
    }

    public func installed(packId: String, version: String) throws -> InstalledPack? {
        let dir = directory(for: packId, version: version)
        guard fileManager.fileExists(atPath: dir.path) else { return nil }
        return try loadInstalled(at: dir)
    }

    // MARK: - Install / download

    /// End-to-end install: ask the registry for a presigned download URL,
    /// fetch the bytes, verify the SHA256, unzip into the cache, and return
    /// the resulting `InstalledPack`. Idempotent — if the (packId, version)
    /// is already installed and verifies clean, the download is skipped.
    public func download(
        packId: String,
        version: String,
        from registry: RegistryClient
    ) async throws -> InstalledPack {
        if let existing = try installed(packId: packId, version: version) {
            return existing
        }
        let info = try await registry.downloadInfo(packId: packId, version: version)
        let bytes: Data
        do {
            let (data, response) = try await session.data(from: info.url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            bytes = data
        } catch {
            throw PackStoreError.downloadFailed(error as any Error & Sendable)
        }
        return try install(zipData: bytes, expectedSHA256: info.sha256)
    }

    /// Install a pack from raw zip bytes whose SHA256 the caller already
    /// knows. Verifies the hash, unzips into a per-version directory, parses
    /// the manifest. Returns the installed value.
    public func install(zipData: Data, expectedSHA256: String) throws -> InstalledPack {
        let actual = Self.sha256Hex(zipData)
        guard actual.lowercased() == expectedSHA256.lowercased() else {
            throw PackStoreError.checksumMismatch(expected: expectedSHA256, actual: actual)
        }

        try ensureRoot()
        let staging = rootDirectory
            .appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }

        do {
            let zip = try PaktlyZip(data: zipData)
            try zip.extract(to: staging)
        } catch let err as PaktlyZipError {
            throw PackStoreError.zipFailed(err)
        } catch {
            throw PackStoreError.zipFailed(error as any Error & Sendable)
        }

        let packRoot = try Self.resolvePackRoot(in: staging, fileManager: fileManager)
        let manifest = try loadManifest(at: packRoot)

        let dest = directory(for: manifest.id, version: manifest.version)
        // Replace any prior install of this exact version.
        if fileManager.fileExists(atPath: dest.path) {
            try? fileManager.removeItem(at: dest)
        }
        try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try fileManager.moveItem(at: packRoot, to: dest)
        } catch {
            throw PackStoreError.io(error as any Error & Sendable)
        }

        let meta = StoredMeta(
            archiveSHA256: actual,
            archiveSizeBytes: Int64(zipData.count),
            installedAt: Date()
        )
        try writeMeta(meta, into: dest)

        return InstalledPack(
            manifest: manifest,
            rootURL: dest,
            installedAt: meta.installedAt,
            archiveSHA256: meta.archiveSHA256,
            archiveSizeBytes: meta.archiveSizeBytes
        )
    }

    // MARK: - Remove

    public func remove(packId: String, version: String) throws {
        let dir = directory(for: packId, version: version)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        do {
            try fileManager.removeItem(at: dir)
        } catch {
            throw PackStoreError.io(error as any Error & Sendable)
        }
    }

    public func removeAll() throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
        do {
            try fileManager.removeItem(at: rootDirectory)
        } catch {
            throw PackStoreError.io(error as any Error & Sendable)
        }
    }

    // MARK: - Internals

    private func ensureRoot() throws {
        if !fileManager.fileExists(atPath: rootDirectory.path) {
            do {
                try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            } catch {
                throw PackStoreError.io(error as any Error & Sendable)
            }
        }
    }

    private func directory(for packId: String, version: String) -> URL {
        rootDirectory
            .appendingPathComponent(packId, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    private func loadInstalled(at directory: URL) throws -> InstalledPack {
        let manifest = try loadManifest(at: directory)
        let meta = (try? readMeta(from: directory)) ?? StoredMeta(
            archiveSHA256: "",
            archiveSizeBytes: 0,
            installedAt: Date(timeIntervalSince1970: 0)
        )
        return InstalledPack(
            manifest: manifest,
            rootURL: directory,
            installedAt: meta.installedAt,
            archiveSHA256: meta.archiveSHA256,
            archiveSizeBytes: meta.archiveSizeBytes
        )
    }

    private func loadManifest(at packRoot: URL) throws -> Manifest {
        let url = packRoot.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: url.path) else {
            throw PackStoreError.manifestMissing
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PackStoreError.io(error as any Error & Sendable)
        }
        do {
            return try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            throw PackStoreError.manifestInvalid(error as any Error & Sendable)
        }
    }

    /// Pack zips conventionally either put files at the archive root or wrap
    /// them in a single top-level folder (GitHub Release zips, for example,
    /// always do the latter). Detect both — look for `manifest.json` at the
    /// staging root, then in any single child directory.
    private static func resolvePackRoot(in staging: URL, fileManager: FileManager) throws -> URL {
        if fileManager.fileExists(atPath: staging.appendingPathComponent("manifest.json").path) {
            return staging
        }
        let children = (try? fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
        let dirs = children.filter { $0.hasDirectoryPath }
        if dirs.count == 1,
           fileManager.fileExists(atPath: dirs[0].appendingPathComponent("manifest.json").path) {
            return dirs[0]
        }
        throw PackStoreError.manifestMissing
    }

    // MARK: - Meta sidecar

    private struct StoredMeta: Codable, Sendable {
        let archiveSHA256: String
        let archiveSizeBytes: Int64
        let installedAt: Date
    }

    private static let metaFilename = ".paktly-meta.json"

    private func writeMeta(_ meta: StoredMeta, into dir: URL) throws {
        let url = dir.appendingPathComponent(Self.metaFilename)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(meta).write(to: url)
        } catch {
            throw PackStoreError.io(error as any Error & Sendable)
        }
    }

    private func readMeta(from dir: URL) throws -> StoredMeta {
        let url = dir.appendingPathComponent(Self.metaFilename)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredMeta.self, from: data)
    }

    // MARK: - SHA256

    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
