import XCTest
import CryptoKit
@testable import PaktlyKit

final class PackStoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaktlyKitTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    private func makeStore(session: URLSession = .shared) -> PackStore {
        PackStore(rootDirectory: tempRoot, session: session)
    }

    // MARK: - Pack zip helper

    private func samplePackZip() -> (Data, sha256: String, manifest: String) {
        let manifestJSON = """
        {
          "schemaVersion": "1.1.0",
          "id": "com.example.test",
          "name": "Test Pack",
          "version": "1.0.0",
          "language": { "code": "ja", "name": "Japanese" },
          "author": { "name": "Tester" },
          "license": "CC-BY-4.0",
          "tags": ["test"],
          "lessons": [
            { "id": "001-hello", "file": "lessons/001-hello.json", "title": "Hello" }
          ]
        }
        """
        let lessonJSON = """
        {
          "id": "001-hello",
          "title": "Hello",
          "blocks": [
            { "type": "explanation", "text": "Test explanation." }
          ]
        }
        """
        let zip = ZipFixture.build([
            .init("manifest.json", manifestJSON),
            .init("lessons/001-hello.json", lessonJSON),
            .init("media/audio/hello.mp3", Data([0xff, 0xfb, 0x90, 0x44]))
        ])
        return (zip, sha256: PackStore.sha256Hex(zip), manifest: manifestJSON)
    }

    // MARK: - Install + read back

    func testInstall_DecodesManifestAndStoresOnDisk() async throws {
        let store = makeStore()
        let (zip, sha, _) = samplePackZip()

        let installed = try await store.install(zipData: zip, expectedSHA256: sha)

        XCTAssertEqual(installed.packId, "com.example.test")
        XCTAssertEqual(installed.version, "1.0.0")
        XCTAssertEqual(installed.archiveSHA256, sha)
        XCTAssertEqual(installed.archiveSizeBytes, Int64(zip.count))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.rootURL.appendingPathComponent("manifest.json").path))
    }

    func testLessonReadback_ReturnsDecodedLesson() async throws {
        let store = makeStore()
        let (zip, sha, _) = samplePackZip()
        let installed = try await store.install(zipData: zip, expectedSHA256: sha)

        let lesson = try installed.lesson(id: "001-hello")
        XCTAssertEqual(lesson.id, "001-hello")
        XCTAssertEqual(lesson.title, "Hello")
        XCTAssertEqual(lesson.blocks.count, 1)
    }

    func testMediaURL_ResolvesExistingFile() async throws {
        let store = makeStore()
        let (zip, sha, _) = samplePackZip()
        let installed = try await store.install(zipData: zip, expectedSHA256: sha)

        let url = installed.mediaURL(forRelativePath: "media/audio/hello.mp3")
        XCTAssertNotNil(url)
        XCTAssertNil(installed.mediaURL(forRelativePath: "media/audio/missing.mp3"))
    }

    func testListInstalled_ReturnsEverything() async throws {
        let store = makeStore()
        let (zip, sha, _) = samplePackZip()
        _ = try await store.install(zipData: zip, expectedSHA256: sha)

        let list = try await store.installedPacks()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].packId, "com.example.test")
    }

    // MARK: - Hash + format defences

    func testInstall_RejectsChecksumMismatch() async throws {
        let store = makeStore()
        let (zip, _, _) = samplePackZip()

        do {
            _ = try await store.install(zipData: zip, expectedSHA256: "0000000000000000")
            XCTFail("expected error")
        } catch let PackStoreError.checksumMismatch(expected, actual) {
            XCTAssertEqual(expected, "0000000000000000")
            XCTAssertEqual(actual, PackStore.sha256Hex(zip))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testInstall_RejectsZipSlipEntry() async throws {
        let store = makeStore()
        let zip = ZipFixture.build([
            .init("manifest.json", #"{"schemaVersion":"1.1.0","id":"a","name":"","version":"1.0.0","language":{"code":"x","name":"x"},"author":{"name":"x"},"license":"x","lessons":[]}"#),
            .init("../escape.txt", "pwned")
        ])
        let sha = PackStore.sha256Hex(zip)

        do {
            _ = try await store.install(zipData: zip, expectedSHA256: sha)
            XCTFail("expected zip-slip rejection")
        } catch PackStoreError.zipFailed {
            // expected — zip-slip surfaces through PaktlyZipError.zipSlip
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testInstall_HandlesGitHubStyleSingleTopLevelFolder() async throws {
        // GitHub Release zips wrap content in a single top-level folder. The
        // resolver must look one directory deep when manifest.json isn't at
        // the archive root.
        let store = makeStore()
        let manifest = #"{"schemaVersion":"1.1.0","id":"com.example.gh","name":"GH","version":"1.0.0","language":{"code":"x","name":"x"},"author":{"name":"x"},"license":"x","lessons":[]}"#
        let zip = ZipFixture.build([
            .init("example-pack-1.0.0/manifest.json", manifest)
        ])
        let sha = PackStore.sha256Hex(zip)

        let installed = try await store.install(zipData: zip, expectedSHA256: sha)
        XCTAssertEqual(installed.packId, "com.example.gh")
    }

    // MARK: - Idempotency + remove

    func testInstall_TwiceIsIdempotent() async throws {
        let store = makeStore()
        let (zip, sha, _) = samplePackZip()

        _ = try await store.install(zipData: zip, expectedSHA256: sha)
        // Second install replaces; should not throw or duplicate.
        let second = try await store.install(zipData: zip, expectedSHA256: sha)
        let list = try await store.installedPacks()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(second.packId, "com.example.test")
    }

    func testRemove_DeletesPackFromDisk() async throws {
        let store = makeStore()
        let (zip, sha, _) = samplePackZip()
        let installed = try await store.install(zipData: zip, expectedSHA256: sha)

        try await store.remove(packId: installed.packId, version: installed.version)

        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.rootURL.path))
        let list = try await store.installedPacks()
        XCTAssertTrue(list.isEmpty)
    }

    // MARK: - Download via registry

    func testDownload_FetchesPresignedURLAndInstalls() async throws {
        let (zip, sha, _) = samplePackZip()
        let session = StubURLProtocol.session()
        let registry = RegistryClient(baseURL: URL(string: "https://api.test")!, session: session)
        let store = PackStore(rootDirectory: tempRoot, session: session)

        // Registry presign + S3 download both go through the stub. Map by URL
        // path so ordering stays explicit.
        StubURLProtocol.install { req in
            if req.url?.path.hasSuffix("/download") == true {
                let json = #"""
                {"url":"https://s3.test/pack.zip","sha256":"\#(sha)","sizeBytes":\#(zip.count),"expiresIn":600}
                """#
                return StubURLProtocol.ok(req, json: json)
            }
            // Otherwise treat as the S3 fetch.
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/zip"])!
            return (resp, zip)
        }

        let installed = try await store.download(
            packId: "com.example.test",
            version: "1.0.0",
            from: registry
        )
        XCTAssertEqual(installed.packId, "com.example.test")

        // Second download must short-circuit (no new HTTP traffic).
        let beforeCount = StubURLProtocol.capturedRequests().count
        _ = try await store.download(
            packId: "com.example.test",
            version: "1.0.0",
            from: registry
        )
        XCTAssertEqual(StubURLProtocol.capturedRequests().count, beforeCount, "second download should be cached")

        StubURLProtocol.uninstall()
    }
}
