import XCTest
@testable import PaktlyKit

final class ManifestTests: XCTestCase {
    func testDecode_v1_1_0() throws {
        let url = try fixture("manifest_v1_1_0")
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        XCTAssertEqual(manifest.schemaVersion, "1.1.0")
        XCTAssertEqual(manifest.id, "com.github.ata.example-nihongo")
        XCTAssertEqual(manifest.version, "0.2.0")
        XCTAssertEqual(manifest.language.code, "ja")
        XCTAssertEqual(manifest.language.nativeName, "日本語")
        XCTAssertEqual(manifest.level, .a1)
        XCTAssertEqual(manifest.uiLanguage, "tr")
        XCTAssertEqual(manifest.lessons.count, 2)
        XCTAssertEqual(manifest.tags, ["japanese", "hiragana", "beginner"])

        let ai = try XCTUnwrap(manifest.aiCapabilities)
        XCTAssertEqual(ai.questionGeneration, true)
        XCTAssertEqual(ai.explanation, true)
        XCTAssertEqual(ai.conversation, false)
        XCTAssertEqual(ai.hint, true)
        XCTAssertTrue(ai.hasAnyEnabled)
    }

    func testDecode_v1_0_0_legacy_StillWorks() throws {
        // A pack pinned at the original schema version must still decode —
        // the SDK is forward-compatible with old packs by design.
        let url = try fixture("manifest_v1_0_0")
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        XCTAssertEqual(manifest.schemaVersion, "1.0.0")
        XCTAssertEqual(manifest.id, "com.example.legacy")
        XCTAssertNil(manifest.aiCapabilities)
        XCTAssertNil(manifest.previousPack)
        XCTAssertNil(manifest.nextPack)
        // Optional collection fields default to empty when missing.
        XCTAssertEqual(manifest.tags, [])
        XCTAssertEqual(manifest.dependencies, [])
    }

    func testRoundTrip_PreservesAllFields() throws {
        let url = try fixture("manifest_v1_1_0")
        let original = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        let encoded = try JSONEncoder().encode(original)
        let roundTripped = try JSONDecoder().decode(Manifest.self, from: encoded)
        XCTAssertEqual(original, roundTripped)
    }

    func testAICapabilities_NoneEnabled_HasAnyEnabledIsFalse() {
        let ai = AICapabilities(
            questionGeneration: false,
            explanation: false,
            conversation: nil,
            hint: nil
        )
        XCTAssertFalse(ai.hasAnyEnabled)
    }
}

// MARK: - fixture helper

private func fixture(_ name: String, file: StaticString = #file, line: UInt = #line) throws -> URL {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
        throw XCTSkip("fixture \(name).json not found in bundle")
    }
    return url
}
