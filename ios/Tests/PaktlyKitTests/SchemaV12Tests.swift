import XCTest
@testable import PaktlyKit

/// Decoding + locale-resolution coverage for the schema 1.2.0 additions:
/// dialogue / kanji / grammar blocks, multi-locale `translations` maps,
/// optional exercise diagnostic tags, and exam-mode lesson fields.
///
/// Tests use inline JSON literals so the cases stay self-contained and
/// independent from any pack fixture's evolution.
final class SchemaV12Tests: XCTestCase {

    // MARK: LocaleResolver

    func testLocaleResolver_PrefersExactPreferredLocale() {
        let result = LocaleResolver.resolve(
            translations: ["tr": "merhaba", "en": "hello", "de": "hallo"],
            legacy: nil,
            preferredLocale: "de",
            uiLanguageFallback: "tr"
        )
        XCTAssertEqual(result, "hallo")
    }

    func testLocaleResolver_FallsBackThroughBCP47Chain() {
        // "zh-Hans-CN" → "zh-Hans" → "zh"; map only has "zh-Hans".
        let result = LocaleResolver.resolve(
            translations: ["zh-Hans": "你好", "en": "hello"],
            legacy: nil,
            preferredLocale: "zh-Hans-CN",
            uiLanguageFallback: nil
        )
        XCTAssertEqual(result, "你好")
    }

    func testLocaleResolver_FallsBackToUILanguage() {
        // Preferred isn't in map; fallback is.
        let result = LocaleResolver.resolve(
            translations: ["tr": "merhaba", "en": "hello"],
            legacy: nil,
            preferredLocale: "fr",
            uiLanguageFallback: "tr"
        )
        XCTAssertEqual(result, "merhaba")
    }

    func testLocaleResolver_FallsBackToLegacyWhenMapEmpty() {
        let result = LocaleResolver.resolve(
            translations: nil,
            legacy: "merhaba",
            preferredLocale: "de",
            uiLanguageFallback: "tr"
        )
        XCTAssertEqual(result, "merhaba")
    }

    func testLocaleResolver_ReturnsNilWhenNothingProvided() {
        let result = LocaleResolver.resolve(
            translations: nil,
            legacy: nil,
            preferredLocale: "tr",
            uiLanguageFallback: nil
        )
        XCTAssertNil(result)
    }

    func testLocaleResolver_DeterministicWhenNoFallbackMatches() {
        // Neither preferred nor fallback is in map; resolver picks
        // the lexicographically first key so behaviour is predictable
        // across runs.
        let result = LocaleResolver.resolve(
            translations: ["en": "hello", "tr": "merhaba"],
            legacy: nil,
            preferredLocale: "ko",
            uiLanguageFallback: "ja"
        )
        XCTAssertEqual(result, "hello")
    }

    // MARK: Vocabulary item — multi-locale

    func testVocabularyItem_DecodesWithTranslationsOnly() throws {
        let json = #"""
        {
          "target": "こんにちは",
          "translations": {
            "tr": "merhaba",
            "en": "hello",
            "de": "hallo"
          }
        }
        """#.data(using: .utf8)!

        let item = try JSONDecoder().decode(VocabularyItem.self, from: json)
        XCTAssertNil(item.translation, "legacy translation should be nil when only translations is present")
        XCTAssertEqual(item.translations?["tr"], "merhaba")
        XCTAssertEqual(item.resolvedTranslation(preferredLocale: "en"), "hello")
        XCTAssertEqual(item.resolvedTranslation(preferredLocale: "fr", uiLanguageFallback: "tr"), "merhaba")
    }

    func testVocabularyItem_LegacyOnlyStillDecodes() throws {
        // 1.0.0 / 1.1.0 packs continue to validate and decode.
        let json = #"""
        { "target": "こんにちは", "translation": "merhaba" }
        """#.data(using: .utf8)!

        let item = try JSONDecoder().decode(VocabularyItem.self, from: json)
        XCTAssertEqual(item.translation, "merhaba")
        XCTAssertNil(item.translations)
        XCTAssertEqual(item.resolvedTranslation(), "merhaba")
    }

    // MARK: Dialogue

    func testDialogueBlock_DecodesAndResolves() throws {
        let json = #"""
        {
          "type": "dialogue",
          "context": "Two students meet on campus.",
          "contexts": {
            "tr": "Kampüste tanışan iki öğrenci."
          },
          "lines": [
            {
              "speaker": "A",
              "target": "はじめまして。私は田中です。",
              "translations": {
                "tr": "Tanıştığımıza memnun oldum. Ben Tanaka.",
                "en": "Nice to meet you. I'm Tanaka."
              },
              "audio": "media/audio/dialogue-1-a.mp3"
            },
            {
              "speaker": "B",
              "target": "山田です。",
              "translation": "I'm Yamada."
            }
          ]
        }
        """#.data(using: .utf8)!

        let lesson = try JSONDecoder().decode(Lesson.self, from: """
        {
          "id": "x",
          "title": "X",
          "blocks": [\(String(data: json, encoding: .utf8)!)]
        }
        """.data(using: .utf8)!)
        guard case .dialogue(let dialogue) = lesson.blocks.first else {
            return XCTFail("expected dialogue block, got \(lesson.blocks.first ?? .explanation(.init(text: "n/a")))")
        }
        XCTAssertEqual(dialogue.lines.count, 2)
        XCTAssertEqual(dialogue.resolvedContext(preferredLocale: "tr"), "Kampüste tanışan iki öğrenci.")
        XCTAssertEqual(dialogue.lines[0].speaker, "A")
        XCTAssertEqual(dialogue.lines[0].audio, "media/audio/dialogue-1-a.mp3")
        XCTAssertEqual(dialogue.lines[0].resolvedTranslation(preferredLocale: "tr"), "Tanıştığımıza memnun oldum. Ben Tanaka.")
        XCTAssertEqual(dialogue.lines[1].resolvedTranslation(preferredLocale: "en"), "I'm Yamada.")
    }

    // MARK: Kanji

    func testKanjiBlock_DecodesWithReadingsAndExamples() throws {
        let json = #"""
        {
          "id": "k1",
          "title": "Kanji",
          "blocks": [
            {
              "type": "kanji",
              "items": [
                {
                  "character": "日",
                  "meanings": { "tr": "gün, güneş", "en": "day, sun" },
                  "onyomi": ["ニチ", "ジツ"],
                  "kunyomi": ["ひ", "-び", "-か"],
                  "strokes": 4,
                  "jlptLevel": "N5",
                  "mnemonics": { "tr": "Pencereden gelen güneş." },
                  "examples": [
                    { "word": "今日", "reading": "きょう", "translations": { "tr": "bugün", "en": "today" } }
                  ]
                }
              ]
            }
          ]
        }
        """#.data(using: .utf8)!

        let lesson = try JSONDecoder().decode(Lesson.self, from: json)
        guard case .kanji(let kanji) = lesson.blocks.first else {
            return XCTFail("expected kanji block")
        }
        let item = try XCTUnwrap(kanji.items.first)
        XCTAssertEqual(item.character, "日")
        XCTAssertEqual(item.onyomi, ["ニチ", "ジツ"])
        XCTAssertEqual(item.kunyomi.count, 3)
        XCTAssertEqual(item.strokes, 4)
        XCTAssertEqual(item.jlptLevel, "N5")
        XCTAssertEqual(item.resolvedMeaning(preferredLocale: "en"), "day, sun")
        XCTAssertEqual(item.resolvedMnemonic(preferredLocale: "tr"), "Pencereden gelen güneş.")
        XCTAssertEqual(item.examples.first?.resolvedTranslation(preferredLocale: "tr"), "bugün")
    }

    // MARK: Grammar

    func testGrammarBlock_DecodesAndResolvesAllSlots() throws {
        let json = #"""
        {
          "id": "g1",
          "title": "Grammar",
          "blocks": [
            {
              "type": "grammar",
              "pattern": "～は～です",
              "level": "N5",
              "meanings": { "tr": "~ dır/dir (kibar)", "en": "~ is ~ (polite)" },
              "formations": { "en": "Noun + は + Noun + です" },
              "usages": { "en": "The most fundamental sentence structure." },
              "watchOuts": { "en": "は here is read 'wa', not 'ha'." },
              "related": ["～は～じゃないです"],
              "examples": [
                { "text": "私は学生です。", "translations": { "tr": "Ben öğrenciyim.", "en": "I am a student." } }
              ]
            }
          ]
        }
        """#.data(using: .utf8)!

        let lesson = try JSONDecoder().decode(Lesson.self, from: json)
        guard case .grammar(let grammar) = lesson.blocks.first else {
            return XCTFail("expected grammar block")
        }
        XCTAssertEqual(grammar.pattern, "～は～です")
        XCTAssertEqual(grammar.level, "N5")
        XCTAssertEqual(grammar.related, ["～は～じゃないです"])
        XCTAssertEqual(grammar.resolvedMeaning(preferredLocale: "tr"), "~ dır/dir (kibar)")
        XCTAssertEqual(grammar.resolvedFormation(preferredLocale: "en"), "Noun + は + Noun + です")
        XCTAssertEqual(grammar.resolvedUsage(preferredLocale: "en"), "The most fundamental sentence structure.")
        XCTAssertEqual(grammar.resolvedWatchOut(preferredLocale: "en"), "は here is read 'wa', not 'ha'.")
        XCTAssertEqual(grammar.examples.first?.resolvedTranslation(preferredLocale: "tr"), "Ben öğrenciyim.")
    }

    // MARK: Exercise — diagnostic tags

    func testExerciseBlock_DecodesSkillsAndDistractorTags() throws {
        let json = #"""
        {
          "id": "x",
          "title": "X",
          "blocks": [
            {
              "type": "exercise",
              "exerciseType": "multipleChoice",
              "data": { "options": ["a","b","c","d"], "correctIndex": 1 },
              "skills": ["vocab.n5", "grammar.particle.wa"],
              "distractorTags": ["confusion-a", null, "confusion-c", "confusion-d"]
            }
          ]
        }
        """#.data(using: .utf8)!

        let lesson = try JSONDecoder().decode(Lesson.self, from: json)
        guard case .exercise(let exercise) = lesson.blocks.first else {
            return XCTFail("expected exercise block")
        }
        XCTAssertEqual(exercise.skills, ["vocab.n5", "grammar.particle.wa"])
        let tags = try XCTUnwrap(exercise.distractorTags)
        XCTAssertEqual(tags.count, 4)
        XCTAssertEqual(tags[0], "confusion-a")
        XCTAssertNil(tags[1])
        XCTAssertEqual(tags[2], "confusion-c")
    }

    func testExerciseBlock_OmitsDiagnosticTags() throws {
        // 1.0.0 / 1.1.0 exercises had no skills / distractorTags fields —
        // those should decode to nil under 1.2.0 too.
        let json = #"""
        {
          "id": "x",
          "title": "X",
          "blocks": [
            { "type": "exercise", "exerciseType": "flashcard" }
          ]
        }
        """#.data(using: .utf8)!

        let lesson = try JSONDecoder().decode(Lesson.self, from: json)
        guard case .exercise(let exercise) = lesson.blocks.first else {
            return XCTFail("expected exercise block")
        }
        XCTAssertNil(exercise.skills)
        XCTAssertNil(exercise.distractorTags)
    }

    // MARK: Exam-mode lesson

    func testLesson_DecodesExamModeFieldsAndDefaults() throws {
        let json = #"""
        {
          "id": "final",
          "title": "Pack 1 final",
          "examMode": true,
          "passingScore": 0.85,
          "timeLimit": 600,
          "drawsFrom": ["001-a", "002-b"],
          "blocks": [
            { "type": "exercise", "exerciseType": "flashcard" }
          ]
        }
        """#.data(using: .utf8)!

        let lesson = try JSONDecoder().decode(Lesson.self, from: json)
        XCTAssertTrue(lesson.examMode)
        XCTAssertEqual(lesson.passingScore, 0.85)
        XCTAssertEqual(lesson.timeLimit, 600)
        XCTAssertEqual(lesson.drawsFrom, ["001-a", "002-b"])
        XCTAssertEqual(lesson.effectivePassingScore, 0.85)
    }

    func testLesson_DefaultsExamModeToFalse() throws {
        // A lesson with no examMode field should decode as a regular lesson —
        // examMode false, no passingScore, drawsFrom empty.
        let json = #"""
        {
          "id": "regular",
          "title": "Regular",
          "blocks": [
            { "type": "exercise", "exerciseType": "flashcard" }
          ]
        }
        """#.data(using: .utf8)!

        let lesson = try JSONDecoder().decode(Lesson.self, from: json)
        XCTAssertFalse(lesson.examMode)
        XCTAssertNil(lesson.passingScore)
        XCTAssertNil(lesson.effectivePassingScore)
        XCTAssertTrue(lesson.drawsFrom.isEmpty)
    }

    func testLesson_ExamModeDefaultsPassingScoreTo80Percent() throws {
        // examMode true but passingScore missing → effectivePassingScore = 0.8
        let json = #"""
        {
          "id": "final",
          "title": "F",
          "examMode": true,
          "blocks": [
            { "type": "exercise", "exerciseType": "flashcard" }
          ]
        }
        """#.data(using: .utf8)!

        let lesson = try JSONDecoder().decode(Lesson.self, from: json)
        XCTAssertTrue(lesson.examMode)
        XCTAssertEqual(lesson.effectivePassingScore, Lesson.defaultPassingScore)
    }

    // MARK: Manifest — translationStatus

    func testManifest_DecodesTranslationStatus() throws {
        // Manifest with mixed provenance: TR + EN native, DE + ZH machine.
        let json = #"""
        {
          "schemaVersion": "1.2.0",
          "id": "com.github.ata.translation-status-test",
          "name": "X",
          "version": "1.0.0",
          "language": { "code": "ja", "name": "Japanese" },
          "uiLanguage": "tr",
          "author": { "name": "Ata" },
          "license": "CC-BY-4.0",
          "lessons": [{ "id": "001", "file": "lessons/001.json" }],
          "translationStatus": {
            "tr":      "native",
            "en":      "native",
            "de":      "machine",
            "zh-Hans": "machine",
            "es":      "reviewed"
          }
        }
        """#.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(Manifest.self, from: json)
        let status = try XCTUnwrap(manifest.translationStatus)
        XCTAssertEqual(status["tr"], .native)
        XCTAssertEqual(status["en"], .native)
        XCTAssertEqual(status["de"], .machine)
        XCTAssertEqual(status["zh-Hans"], .machine)
        XCTAssertEqual(status["es"], .reviewed)
    }

    func testManifest_TranslationStatusOptional_DecodesNil() throws {
        let json = #"""
        {
          "schemaVersion": "1.2.0",
          "id": "com.github.ata.no-status",
          "name": "X",
          "version": "1.0.0",
          "language": { "code": "ja", "name": "Japanese" },
          "author": { "name": "Ata" },
          "license": "CC-BY-4.0",
          "lessons": [{ "id": "001", "file": "lessons/001.json" }]
        }
        """#.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(Manifest.self, from: json)
        XCTAssertNil(manifest.translationStatus)
    }
}
