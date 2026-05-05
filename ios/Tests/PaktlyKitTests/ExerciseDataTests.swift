import XCTest
@testable import PaktlyKit

/// Cover every mechanic family with a parse round-trip: build an
/// `ExerciseBlock` whose `data` is the raw JSON for that family, ensure
/// `parseData()` returns the typed variant with the expected fields. Each
/// test also asserts the reverse-mapping (the exerciseType maps to the
/// family the test claims).
final class ExerciseDataTests: XCTestCase {

    private func decode<T: Decodable>(_ t: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Catalog completeness

    func testExerciseType_HasThirtyCases() {
        XCTAssertEqual(ExerciseType.allCases.count, 30)
    }

    func testEveryExerciseType_MapsToOneFamily() {
        let counts = Dictionary(grouping: ExerciseType.allCases, by: { $0.family })
            .mapValues { $0.count }
        XCTAssertEqual(counts[.recall], 4)
        XCTAssertEqual(counts[.multipleChoice], 5)
        XCTAssertEqual(counts[.typing], 3)
        XCTAssertEqual(counts[.listening], 3)
        XCTAssertEqual(counts[.matching], 3)
        XCTAssertEqual(counts[.fillInBlank], 3)
        XCTAssertEqual(counts[.wordOrder], 2)
        XCTAssertEqual(counts[.reading], 3)
        XCTAssertEqual(counts[.production], 2)
        XCTAssertEqual(counts[.categorization], 2)
    }

    // MARK: - Round-trip per family

    func testRecall_ParsesFlashcardData() throws {
        let json = """
        {
          "type": "exercise",
          "exerciseType": "flashcardReverse",
          "data": {
            "front": { "text": "merhaba" },
            "back":  { "text": "こんにちは", "audio": "media/audio/konnichiwa.mp3" },
            "hint": "informal greeting"
          }
        }
        """
        let block = try decode(ExerciseBlock.self, json)
        guard case let .recall(data) = try XCTUnwrap(try block.parseData()) else {
            return XCTFail("expected recall family")
        }
        XCTAssertEqual(data.front.text, "merhaba")
        XCTAssertEqual(data.back.audio, "media/audio/konnichiwa.mp3")
        XCTAssertEqual(data.hint, "informal greeting")
    }

    func testMultipleChoice_ParsesPromptOptionsCorrectIndex() throws {
        let json = """
        {
          "type": "exercise",
          "exerciseType": "multipleChoiceAudio",
          "data": {
            "prompt": { "audio": "media/audio/konnichiwa.mp3" },
            "options": ["merhaba", "günaydın", "iyi geceler", "teşekkürler"],
            "correctIndex": 0,
            "explanation": "Daytime greeting"
          }
        }
        """
        let block = try decode(ExerciseBlock.self, json)
        guard case let .multipleChoice(data) = try XCTUnwrap(try block.parseData()) else {
            return XCTFail("expected multipleChoice family")
        }
        XCTAssertEqual(data.options.count, 4)
        XCTAssertEqual(data.correctIndex, 0)
        XCTAssertEqual(data.prompt.audio, "media/audio/konnichiwa.mp3")
        XCTAssertEqual(data.explanation, "Daytime greeting")
    }

    func testTyping_AcceptsAlternativesAndDefaults() throws {
        let json = """
        {
          "type": "exercise",
          "exerciseType": "typing",
          "data": {
            "prompt": { "text": "Hello (informal)" },
            "answer": "こんにちは",
            "acceptedAlternatives": ["コンニチハ"]
          }
        }
        """
        let block = try decode(ExerciseBlock.self, json)
        guard case let .typing(data) = try XCTUnwrap(try block.parseData()) else {
            return XCTFail("expected typing family")
        }
        XCTAssertEqual(data.answer, "こんにちは")
        XCTAssertEqual(data.acceptedAlternatives, ["コンニチハ"])
        XCTAssertFalse(data.caseSensitive, "default must be false when omitted")
    }

    func testListening_DictationVariantUsesAnswerField() throws {
        let json = """
        {
          "type": "exercise",
          "exerciseType": "dictation",
          "data": {
            "audio": "media/audio/sentence.mp3",
            "answer": "今日はいい天気ですね",
            "transcript": "今日はいい天気ですね"
          }
        }
        """
        let block = try decode(ExerciseBlock.self, json)
        guard case let .listening(data) = try XCTUnwrap(try block.parseData()) else {
            return XCTFail("expected listening family")
        }
        XCTAssertEqual(data.audio, "media/audio/sentence.mp3")
        XCTAssertEqual(data.answer, "今日はいい天気ですね")
        XCTAssertNil(data.options, "dictation does not use options")
    }

    func testMatching_PairsRoundTrip() throws {
        let json = """
        {
          "type": "exercise",
          "exerciseType": "matching",
          "data": {
            "pairs": [
              { "left": { "text": "犬" }, "right": { "text": "köpek" } },
              { "left": { "text": "猫" }, "right": { "text": "kedi" } }
            ]
          }
        }
        """
        let block = try decode(ExerciseBlock.self, json)
        guard case let .matching(data) = try XCTUnwrap(try block.parseData()) else {
            return XCTFail("expected matching family")
        }
        XCTAssertEqual(data.pairs.count, 2)
        XCTAssertEqual(data.pairs[0].left.text, "犬")
        XCTAssertEqual(data.pairs[1].right.text, "kedi")
    }

    func testFillInBlank_TemplateAndAnswers() throws {
        let json = """
        {
          "type": "exercise",
          "exerciseType": "fillInBlank",
          "data": {
            "template": "{{1}} さん、おはようございます",
            "answers": ["田中"],
            "acceptedAlternatives": [["タナカ", "tanaka"]]
          }
        }
        """
        let block = try decode(ExerciseBlock.self, json)
        guard case let .fillInBlank(data) = try XCTUnwrap(try block.parseData()) else {
            return XCTFail("expected fillInBlank family")
        }
        XCTAssertTrue(data.template.contains("{{1}}"))
        XCTAssertEqual(data.answers, ["田中"])
        XCTAssertEqual(data.acceptedAlternatives, [["タナカ", "tanaka"]])
        XCTAssertNil(data.options)
    }

    func testWordOrder_TilesAndOrder() throws {
        let json = """
        {
          "type": "exercise",
          "exerciseType": "wordOrder",
          "data": {
            "tiles": ["は", "今日", "天気", "いい"],
            "correctOrder": [1, 0, 3, 2],
            "translation": "Today the weather is nice"
          }
        }
        """
        let block = try decode(ExerciseBlock.self, json)
        guard case let .wordOrder(data) = try XCTUnwrap(try block.parseData()) else {
            return XCTFail("expected wordOrder family")
        }
        XCTAssertEqual(data.correctOrder, [1, 0, 3, 2])
        XCTAssertEqual(data.translation, "Today the weather is nice")
    }

    func testReading_MixedQuestionKinds() throws {
        let json = """
        {
          "type": "exercise",
          "exerciseType": "readingComprehension",
          "data": {
            "passage": "東京は日本の首都です。",
            "questions": [
              { "kind": "trueFalse", "prompt": "Tokyo is the capital", "truthy": true },
              {
                "kind": "multipleChoice",
                "prompt": "Tokyo is in",
                "options": ["China", "Japan", "Korea"],
                "correctIndex": 1
              }
            ],
            "glossary": { "首都": "capital" }
          }
        }
        """
        let block = try decode(ExerciseBlock.self, json)
        guard case let .reading(data) = try XCTUnwrap(try block.parseData()) else {
            return XCTFail("expected reading family")
        }
        XCTAssertEqual(data.questions.count, 2)
        XCTAssertEqual(data.questions[0].kind, .trueFalse)
        XCTAssertEqual(data.questions[1].correctIndex, 1)
        XCTAssertEqual(data.glossary["首都"], "capital")
    }

    func testProduction_RequiredWordsAndDefaults() throws {
        let json = """
        {
          "type": "exercise",
          "exerciseType": "translateSentence",
          "data": {
            "prompt": { "text": "I drink water every morning" },
            "referenceAnswer": "毎朝水を飲みます",
            "requiredWords": ["毎朝", "水"]
          }
        }
        """
        let block = try decode(ExerciseBlock.self, json)
        guard case let .production(data) = try XCTUnwrap(try block.parseData()) else {
            return XCTFail("expected production family")
        }
        XCTAssertEqual(data.requiredWords, ["毎朝", "水"])
        XCTAssertNil(data.minLength)
    }

    func testCategorization_OddOneOutVariant() throws {
        let json = """
        {
          "type": "exercise",
          "exerciseType": "oddOneOut",
          "data": {
            "items": ["りんご", "バナナ", "ぶどう", "車"],
            "oddIndex": 3,
            "explanation": "車 is a vehicle, the others are fruits"
          }
        }
        """
        let block = try decode(ExerciseBlock.self, json)
        guard case let .categorization(data) = try XCTUnwrap(try block.parseData()) else {
            return XCTFail("expected categorization family")
        }
        XCTAssertEqual(data.oddIndex, 3)
        XCTAssertTrue(data.categories.isEmpty)
    }

    func testCategorization_SortVariant() throws {
        let json = """
        {
          "type": "exercise",
          "exerciseType": "categorySort",
          "data": {
            "items": ["りんご", "車", "バナナ", "電車"],
            "categories": [
              { "name": "fruit",   "items": ["りんご", "バナナ"] },
              { "name": "vehicle", "items": ["車", "電車"] }
            ]
          }
        }
        """
        let block = try decode(ExerciseBlock.self, json)
        guard case let .categorization(data) = try XCTUnwrap(try block.parseData()) else {
            return XCTFail("expected categorization family")
        }
        XCTAssertEqual(data.categories.count, 2)
        XCTAssertEqual(data.categories[0].name, "fruit")
        XCTAssertNil(data.oddIndex)
    }

    // MARK: - Edge cases

    func testParseData_ReturnsNilWhenDataAbsent() throws {
        let json = """
        { "type": "exercise", "exerciseType": "flashcard" }
        """
        let block = try decode(ExerciseBlock.self, json)
        XCTAssertNil(try block.parseData())
    }

    func testParseData_ThrowsOnPayloadFamilyMismatch() throws {
        // Declared type is "matching" (needs `pairs`), but data has flashcard
        // shape. Surfacing an error here lets the runner refuse to render
        // garbage rather than silently misinterpret it.
        let json = """
        {
          "type": "exercise",
          "exerciseType": "matching",
          "data": { "front": { "text": "x" }, "back": { "text": "y" } }
        }
        """
        let block = try decode(ExerciseBlock.self, json)
        XCTAssertThrowsError(try block.parseData())
    }
}
