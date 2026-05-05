import XCTest
@testable import PaktlyKit

final class LessonTests: XCTestCase {
    func testDecode_HiraganaLesson_v1_1_0() throws {
        guard let url = Bundle.module.url(forResource: "lesson_001_v1_1_0", withExtension: "json") else {
            throw XCTSkip("fixture missing")
        }
        let data = try Data(contentsOf: url)
        let lesson = try JSONDecoder().decode(Lesson.self, from: data)

        XCTAssertEqual(lesson.id, "001-hiragana-aiueo")
        XCTAssertEqual(lesson.estimatedMinutes, 10)
        XCTAssertGreaterThanOrEqual(lesson.blocks.count, 3)

        // First block is an explanation, not a vocabulary or exercise.
        switch lesson.blocks[0] {
        case .explanation(let b):
            XCTAssertTrue(b.text.contains("hiragana"))
        default:
            XCTFail("expected first block to be .explanation, got \(lesson.blocks[0])")
        }

        // Find the vocabulary block and check v1.1 fields populate.
        let vocab = lesson.blocks.compactMap { block -> VocabularyBlock? in
            if case .vocabulary(let v) = block { return v }
            return nil
        }.first
        let v = try XCTUnwrap(vocab, "expected one vocabulary block")
        XCTAssertEqual(v.items.count, 5)

        // Each item should carry an IPA string and at least one example —
        // these are the hallmark v1.1 additions in the migrated example pack.
        for item in v.items {
            XCTAssertNotNil(item.ipa, "vocab item \(item.target) missing IPA")
            XCTAssertFalse(item.examples.isEmpty, "vocab item \(item.target) has no examples")
        }
    }

    func testDecode_UnknownBlockType_Throws() {
        let json = #"""
        {
          "id": "x",
          "title": "X",
          "blocks": [
            { "type": "imaginary", "foo": "bar" }
          ]
        }
        """#.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(Lesson.self, from: json)) { err in
            // Make sure the error mentions the offending type — useful when
            // an SDK consumer is debugging a malformed lesson.
            let desc = String(describing: err)
            XCTAssertTrue(desc.contains("imaginary"), "error should mention unknown block type, got \(desc)")
        }
    }

    func testEncode_BlockUnion_RoundTrips() throws {
        let lesson = Lesson(
            id: "demo",
            title: "Demo",
            blocks: [
                .explanation(ExplanationBlock(text: "hi")),
                .vocabulary(VocabularyBlock(items: [
                    VocabularyItem(
                        target: "猫", translation: "cat",
                        ipa: "/neko/",
                        examples: [.init(text: "猫がいる", translation: "there is a cat")]
                    ),
                ])),
                .exercise(ExerciseBlock(
                    exerciseType: .flashcard,
                    prompt: "what is 猫?"
                )),
            ]
        )
        let data = try JSONEncoder().encode(lesson)
        let decoded = try JSONDecoder().decode(Lesson.self, from: data)
        XCTAssertEqual(lesson, decoded)
    }
}
