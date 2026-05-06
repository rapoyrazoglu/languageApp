package pack

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

// minimalManifest is a manifest that satisfies all required fields. Tests tweak
// fields on a copy to exercise specific validation paths.
func minimalManifest() map[string]any {
	return map[string]any{
		"schemaVersion": "1.0.0",
		"id":            "com.github.test.minimal",
		"name":          "Minimal",
		"version":       "1.0.0",
		"language": map[string]any{
			"code": "ja",
			"name": "Japanese",
		},
		"author":  map[string]any{"name": "Test"},
		"license": "MIT",
		"lessons": []any{
			map[string]any{"id": "001", "file": "lessons/001.json"},
		},
	}
}

// minimalLesson satisfies the lesson schema with one explanation block.
func minimalLesson() map[string]any {
	return map[string]any{
		"id":    "001",
		"title": "Hello",
		"blocks": []any{
			map[string]any{"type": "explanation", "text": "Hi"},
		},
	}
}

// buildZip creates a zip from a map of file → content (string or marshalable).
// If withRoot is non-empty, every entry is nested under that directory.
func buildZip(t *testing.T, withRoot string, entries map[string]any) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, body := range entries {
		full := name
		if withRoot != "" {
			full = withRoot + "/" + name
		}
		f, err := zw.Create(full)
		if err != nil {
			t.Fatal(err)
		}
		switch v := body.(type) {
		case string:
			_, _ = f.Write([]byte(v))
		case []byte:
			_, _ = f.Write(v)
		default:
			b, err := json.Marshal(v)
			if err != nil {
				t.Fatal(err)
			}
			_, _ = f.Write(b)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func newValidator(t *testing.T) *Validator {
	t.Helper()
	v, err := NewValidator()
	if err != nil {
		t.Fatal(err)
	}
	return v
}

func TestValidate_HappyPath_FlatLayout(t *testing.T) {
	v := newValidator(t)
	z := buildZip(t, "", map[string]any{
		"manifest.json":    minimalManifest(),
		"lessons/001.json": minimalLesson(),
	})
	res := v.ValidateZip(z)
	if !res.Ok() {
		t.Fatalf("expected valid, got errors: %+v", res.Errors)
	}
	if res.Manifest == nil || res.Manifest.ID != "com.github.test.minimal" {
		t.Fatalf("manifest not parsed: %+v", res.Manifest)
	}
	if res.SHA256 == "" || res.Size == 0 {
		t.Fatal("expected sha256 + size populated")
	}
}

func TestValidate_HappyPath_NestedRoot(t *testing.T) {
	// Many GitHub release zips wrap everything in a single top-level dir
	// (e.g. "nihongo-1.0.0/"). The validator should normalize that.
	v := newValidator(t)
	z := buildZip(t, "nihongo-1.0.0", map[string]any{
		"manifest.json":    minimalManifest(),
		"lessons/001.json": minimalLesson(),
	})
	res := v.ValidateZip(z)
	if !res.Ok() {
		t.Fatalf("expected valid, got errors: %+v", res.Errors)
	}
}

func TestValidate_RejectsZipSlip(t *testing.T) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	f, _ := zw.Create("../escape.txt")
	_, _ = f.Write([]byte("nope"))
	_ = zw.Close()

	res := newValidator(t).ValidateZip(buf.Bytes())
	if res.Ok() {
		t.Fatal("expected errors for zip-slip path")
	}
	if !containsMessage(res.Errors, "unsafe path") {
		t.Fatalf("expected zip-slip error, got %+v", res.Errors)
	}
}

func TestValidate_MissingManifest(t *testing.T) {
	v := newValidator(t)
	z := buildZip(t, "", map[string]any{
		"lessons/001.json": minimalLesson(),
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected error")
	}
	if !containsMessage(res.Errors, "manifest.json not found") {
		t.Fatalf("got %+v", res.Errors)
	}
}

func TestValidate_BadSemver(t *testing.T) {
	v := newValidator(t)
	m := minimalManifest()
	m["version"] = "not-a-semver"
	z := buildZip(t, "", map[string]any{
		"manifest.json":    m,
		"lessons/001.json": minimalLesson(),
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected schema validation error for bad semver")
	}
}

func TestValidate_BadIDFormat(t *testing.T) {
	v := newValidator(t)
	m := minimalManifest()
	m["id"] = "not_reverse_dns" // schema requires reverse-DNS pattern
	z := buildZip(t, "", map[string]any{
		"manifest.json":    m,
		"lessons/001.json": minimalLesson(),
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected schema error for non-reverse-DNS id")
	}
}

func TestValidate_LessonReferencedButMissing(t *testing.T) {
	v := newValidator(t)
	m := minimalManifest()
	m["lessons"] = []any{
		map[string]any{"id": "001", "file": "lessons/001.json"},
		map[string]any{"id": "002", "file": "lessons/missing.json"},
	}
	z := buildZip(t, "", map[string]any{
		"manifest.json":    m,
		"lessons/001.json": minimalLesson(),
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected error for missing lesson")
	}
	if !containsMessage(res.Errors, "missing in zip") {
		t.Fatalf("got %+v", res.Errors)
	}
}

func TestValidate_LessonIDMismatch(t *testing.T) {
	v := newValidator(t)
	wrong := minimalLesson()
	wrong["id"] = "wrong-id"
	z := buildZip(t, "", map[string]any{
		"manifest.json":    minimalManifest(),
		"lessons/001.json": wrong,
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected error for lesson id mismatch")
	}
	if !containsMessage(res.Errors, "does not match manifest id") {
		t.Fatalf("got %+v", res.Errors)
	}
}

func TestValidate_MissingMediaReference(t *testing.T) {
	v := newValidator(t)
	lesson := map[string]any{
		"id":    "001",
		"title": "Audio",
		"blocks": []any{
			map[string]any{
				"type": "vocabulary",
				"items": []any{
					map[string]any{
						"target":      "あ",
						"translation": "a",
						"audio":       "media/audio/missing.mp3",
					},
				},
			},
		},
	}
	z := buildZip(t, "", map[string]any{
		"manifest.json":    minimalManifest(),
		"lessons/001.json": lesson,
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected error for missing media")
	}
	if !containsMessage(res.Errors, "missing media file") {
		t.Fatalf("got %+v", res.Errors)
	}
}

func TestValidate_MediaPresentSatisfies(t *testing.T) {
	v := newValidator(t)
	lesson := map[string]any{
		"id":    "001",
		"title": "Audio",
		"blocks": []any{
			map[string]any{
				"type": "vocabulary",
				"items": []any{
					map[string]any{
						"target":      "あ",
						"translation": "a",
						"audio":       "media/audio/a.mp3",
					},
				},
			},
		},
	}
	z := buildZip(t, "", map[string]any{
		"manifest.json":     minimalManifest(),
		"lessons/001.json":  lesson,
		"media/audio/a.mp3": []byte{0xff, 0xfb, 0x90, 0x44}, // bogus mp3 bytes — only existence is checked
	})
	res := v.ValidateZip(z)
	if !res.Ok() {
		t.Fatalf("expected valid, got %+v", res.Errors)
	}
}

func TestValidate_NotAZip(t *testing.T) {
	res := newValidator(t).ValidateZip([]byte("not even close to a zip"))
	if res.Ok() {
		t.Fatal("expected error for non-zip bytes")
	}
}

func TestValidate_InvalidJSONManifest(t *testing.T) {
	v := newValidator(t)
	z := buildZip(t, "", map[string]any{
		"manifest.json":    "{ this is not json",
		"lessons/001.json": minimalLesson(),
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected error for invalid manifest JSON")
	}
}

func containsMessage(errs []ValidationErr, substr string) bool {
	for _, e := range errs {
		if strings.Contains(e.Message, substr) {
			return true
		}
	}
	return false
}

// --- pack format v1.1 ---

// minimalManifestV11 is the same as minimalManifest but bumped to schema 1.1.0
// with the new optional fields populated.
func minimalManifestV11() map[string]any {
	m := minimalManifest()
	m["schemaVersion"] = "1.1.0"
	m["aiCapabilities"] = map[string]any{
		"questionGeneration": true,
		"explanation":        true,
		"conversation":       false,
		"hint":               false,
	}
	m["previousPack"] = "com.github.test.intro"
	m["nextPack"] = "com.github.test.next"
	return m
}

// vocabLessonWithExamples is a lesson exercising the v1.1 vocabulary additions:
// per-item ipa, examples[] with their own audio refs.
func vocabLessonWithExamples() map[string]any {
	return map[string]any{
		"id":    "001",
		"title": "Greetings",
		"blocks": []any{
			map[string]any{
				"type": "vocabulary",
				"items": []any{
					map[string]any{
						"target":      "こんにちは",
						"translation": "merhaba",
						"ipa":         "/koɲɲitɕiwa/",
						"audio":       "media/audio/konnichiwa.mp3",
						"examples": []any{
							map[string]any{
								"text":        "こんにちは、田中さん",
								"translation": "merhaba Tanaka-san",
								"audio":       "media/audio/example-1.mp3",
							},
						},
					},
				},
			},
		},
	}
}

func TestValidate_V11_ManifestAndExamples_HappyPath(t *testing.T) {
	v := newValidator(t)
	z := buildZip(t, "", map[string]any{
		"manifest.json":              minimalManifestV11(),
		"lessons/001.json":           vocabLessonWithExamples(),
		"media/audio/konnichiwa.mp3": []byte{0xff, 0xfb, 0x90, 0x44}, // tiny mp3-ish header
		"media/audio/example-1.mp3":  []byte{0xff, 0xfb, 0x90, 0x44},
	})
	res := v.ValidateZip(z)
	if !res.Ok() {
		t.Fatalf("v1.1 happy path failed: %+v", res.Errors)
	}
	if res.Manifest.SchemaVersion != "1.1.0" {
		t.Fatalf("schemaVersion = %q, want 1.1.0", res.Manifest.SchemaVersion)
	}
	if res.Manifest.AICapabilities == nil || !res.Manifest.AICapabilities.QuestionGeneration {
		t.Fatalf("aiCapabilities not parsed: %+v", res.Manifest.AICapabilities)
	}
	if res.Manifest.PreviousPack != "com.github.test.intro" {
		t.Fatalf("previousPack = %q", res.Manifest.PreviousPack)
	}
}

func TestValidate_V11_ExampleAudioMustExist(t *testing.T) {
	v := newValidator(t)
	// example references an audio file that's NOT in the zip
	z := buildZip(t, "", map[string]any{
		"manifest.json":              minimalManifestV11(),
		"lessons/001.json":           vocabLessonWithExamples(),
		"media/audio/konnichiwa.mp3": []byte{0xff, 0xfb},
		// media/audio/example-1.mp3 omitted on purpose
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected error for missing example audio file")
	}
	if !containsMessage(res.Errors, "example-1.mp3") {
		t.Fatalf("expected missing-media error mentioning example-1.mp3, got %+v", res.Errors)
	}
}

func TestValidate_V11_OldPackStillValidates(t *testing.T) {
	// A schema 1.0.0 manifest with no v1.1 fields must keep validating —
	// backwards compatibility is the whole point of bumping minor.
	v := newValidator(t)
	m := minimalManifest() // schema 1.0.0
	z := buildZip(t, "", map[string]any{
		"manifest.json":    m,
		"lessons/001.json": minimalLesson(),
	})
	res := v.ValidateZip(z)
	if !res.Ok() {
		t.Fatalf("legacy v1.0.0 pack failed: %+v", res.Errors)
	}
	if res.Manifest.AICapabilities != nil {
		t.Fatal("aiCapabilities should be nil for v1.0.0 pack with no field")
	}
}

func TestValidate_V11_RejectsUnknownSchemaVersion(t *testing.T) {
	v := newValidator(t)
	m := minimalManifest()
	m["schemaVersion"] = "2.0.0" // never published
	z := buildZip(t, "", map[string]any{
		"manifest.json":    m,
		"lessons/001.json": minimalLesson(),
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected error for unknown schemaVersion 2.0.0")
	}
}

func TestValidate_V11_RejectsUnknownAICapabilityField(t *testing.T) {
	v := newValidator(t)
	m := minimalManifestV11()
	m["aiCapabilities"] = map[string]any{
		"questionGeneration": true,
		"madeUpFeature":      true, // additionalProperties: false should reject
	}
	z := buildZip(t, "", map[string]any{
		"manifest.json":    m,
		"lessons/001.json": minimalLesson(),
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected error for unknown aiCapabilities field")
	}
}

// --- pack format v1.2.0 ---

// minimalManifestV12 bumps the schema version. No new manifest-level fields in
// 1.2.0 — all the additions are at the lesson level.
func minimalManifestV12() map[string]any {
	m := minimalManifestV11()
	m["schemaVersion"] = "1.2.0"
	return m
}

// vocabLessonV12TranslationsMap exercises the multi-locale translation map:
// the vocab item drops the legacy `translation` and uses only `translations`.
func vocabLessonV12TranslationsMap() map[string]any {
	return map[string]any{
		"id":    "001",
		"title": "Greetings",
		"blocks": []any{
			map[string]any{
				"type": "vocabulary",
				"items": []any{
					map[string]any{
						"target": "こんにちは",
						"translations": map[string]any{
							"tr":      "merhaba",
							"en":      "hello",
							"de":      "hallo",
							"zh-Hans": "你好",
							"es":      "hola",
						},
						"ipa": "/koɲɲitɕiwa/",
						"examples": []any{
							map[string]any{
								"text": "こんにちは、田中さん",
								"translations": map[string]any{
									"tr": "merhaba Tanaka-san",
									"en": "hello Tanaka-san",
								},
							},
						},
					},
				},
			},
		},
	}
}

func TestValidate_V12_TranslationsMap_HappyPath(t *testing.T) {
	v := newValidator(t)
	z := buildZip(t, "", map[string]any{
		"manifest.json":    minimalManifestV12(),
		"lessons/001.json": vocabLessonV12TranslationsMap(),
	})
	res := v.ValidateZip(z)
	if !res.Ok() {
		t.Fatalf("v1.2 translations map happy path failed: %+v", res.Errors)
	}
	if res.Manifest.SchemaVersion != "1.2.0" {
		t.Fatalf("schemaVersion = %q, want 1.2.0", res.Manifest.SchemaVersion)
	}
}

func TestValidate_V12_VocabItem_RequiresTranslationOrTranslations(t *testing.T) {
	v := newValidator(t)
	lesson := map[string]any{
		"id":    "001",
		"title": "Bad",
		"blocks": []any{
			map[string]any{
				"type": "vocabulary",
				"items": []any{
					map[string]any{
						"target": "こんにちは",
						// neither translation nor translations
					},
				},
			},
		},
	}
	z := buildZip(t, "", map[string]any{
		"manifest.json":    minimalManifestV12(),
		"lessons/001.json": lesson,
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected validation error: vocab item missing both translation and translations")
	}
}

func TestValidate_V12_TranslationsMap_RejectsBadLocaleKey(t *testing.T) {
	v := newValidator(t)
	lesson := map[string]any{
		"id":    "001",
		"title": "Bad",
		"blocks": []any{
			map[string]any{
				"type": "vocabulary",
				"items": []any{
					map[string]any{
						"target": "こんにちは",
						"translations": map[string]any{
							"TR": "merhaba", // uppercase locale key — schema requires lowercase
						},
					},
				},
			},
		},
	}
	z := buildZip(t, "", map[string]any{
		"manifest.json":    minimalManifestV12(),
		"lessons/001.json": lesson,
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected validation error: invalid locale key in translations map")
	}
}

// dialogueKanjiGrammarLesson exercises the three new 1.2.0 block types in one
// lesson. It also references audio files that must exist in the zip.
func dialogueKanjiGrammarLesson() map[string]any {
	return map[string]any{
		"id":    "001",
		"title": "Foundations",
		"blocks": []any{
			map[string]any{
				"type":    "dialogue",
				"context": "Two students meeting on campus.",
				"contexts": map[string]any{
					"tr": "Kampüste tanışan iki öğrenci.",
					"en": "Two students meeting on campus.",
				},
				"lines": []any{
					map[string]any{
						"speaker": "A",
						"target":  "はじめまして。私は田中です。",
						"translations": map[string]any{
							"tr": "Tanıştığımıza memnun oldum. Ben Tanaka.",
							"en": "Nice to meet you. I'm Tanaka.",
						},
						"audio": "media/audio/dialogue-1-a.mp3",
					},
					map[string]any{
						"speaker":     "B",
						"target":      "山田です。よろしく。",
						"translation": "I'm Yamada. Pleased to meet you.",
					},
				},
			},
			map[string]any{
				"type": "kanji",
				"items": []any{
					map[string]any{
						"character": "日",
						"meanings": map[string]any{
							"tr": "gün, güneş",
							"en": "day, sun",
						},
						"onyomi":    []any{"ニチ", "ジツ"},
						"kunyomi":   []any{"ひ", "-び", "-か"},
						"strokes":   4,
						"jlptLevel": "N5",
						"mnemonics": map[string]any{
							"tr": "Bir pencereden gelen güneş.",
							"en": "Sun seen through a window.",
						},
						"examples": []any{
							map[string]any{
								"word":    "今日",
								"reading": "きょう",
								"translations": map[string]any{
									"tr": "bugün",
									"en": "today",
								},
							},
						},
					},
				},
			},
			map[string]any{
				"type":    "grammar",
				"pattern": "～は～です",
				"level":   "N5",
				"meanings": map[string]any{
					"tr": "~ dır/dir (kibar)",
					"en": "~ is ~ (polite)",
				},
				"formations": map[string]any{
					"tr": "İsim + は + İsim + です",
					"en": "Noun + は + Noun + です",
				},
				"usages": map[string]any{
					"tr": "Japonca'nın en temel cümle yapısı.",
					"en": "Japanese's most fundamental sentence structure.",
				},
				"watchOuts": map[string]any{
					"tr": "は burada 'wa' okunur, 'ha' değil.",
					"en": "は here is read 'wa', not 'ha'.",
				},
				"related": []any{"～は～じゃないです", "～は～でした"},
				"examples": []any{
					map[string]any{
						"text": "私は学生です。",
						"translations": map[string]any{
							"tr": "Ben öğrenciyim.",
							"en": "I am a student.",
						},
					},
				},
			},
		},
	}
}

func TestValidate_V12_NewBlocks_HappyPath(t *testing.T) {
	v := newValidator(t)
	z := buildZip(t, "", map[string]any{
		"manifest.json":                minimalManifestV12(),
		"lessons/001.json":             dialogueKanjiGrammarLesson(),
		"media/audio/dialogue-1-a.mp3": []byte{0xff, 0xfb, 0x90, 0x44},
	})
	res := v.ValidateZip(z)
	if !res.Ok() {
		t.Fatalf("v1.2 dialogue/kanji/grammar happy path failed: %+v", res.Errors)
	}
}

func TestValidate_V12_DialogueAudioMustExist(t *testing.T) {
	v := newValidator(t)
	// dialogue references audio that's NOT in the zip
	z := buildZip(t, "", map[string]any{
		"manifest.json":    minimalManifestV12(),
		"lessons/001.json": dialogueKanjiGrammarLesson(),
		// media/audio/dialogue-1-a.mp3 omitted on purpose
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected error for missing dialogue audio file")
	}
	if !containsMessage(res.Errors, "dialogue-1-a.mp3") {
		t.Fatalf("expected missing-media error mentioning dialogue audio, got %+v", res.Errors)
	}
}

func TestValidate_V12_KanjiBlock_RequiresMeaningOrMeanings(t *testing.T) {
	v := newValidator(t)
	lesson := map[string]any{
		"id":    "001",
		"title": "Bad kanji",
		"blocks": []any{
			map[string]any{
				"type": "kanji",
				"items": []any{
					map[string]any{
						"character": "日",
						// neither meaning nor meanings
						"onyomi": []any{"ニチ"},
					},
				},
			},
		},
	}
	z := buildZip(t, "", map[string]any{
		"manifest.json":    minimalManifestV12(),
		"lessons/001.json": lesson,
	})
	res := v.ValidateZip(z)
	if res.Ok() {
		t.Fatal("expected error: kanji item missing meaning and meanings")
	}
}

func TestValidate_V12_GrammarBlock_AcceptsMinimal(t *testing.T) {
	v := newValidator(t)
	lesson := map[string]any{
		"id":    "001",
		"title": "Grammar minimal",
		"blocks": []any{
			map[string]any{
				"type":    "grammar",
				"pattern": "～は～です",
				"meaning": "~ is ~",
			},
		},
	}
	z := buildZip(t, "", map[string]any{
		"manifest.json":    minimalManifestV12(),
		"lessons/001.json": lesson,
	})
	res := v.ValidateZip(z)
	if !res.Ok() {
		t.Fatalf("minimal grammar block should validate, got %+v", res.Errors)
	}
}

func TestValidate_V12_ExerciseSkillsAndDistractorTags(t *testing.T) {
	v := newValidator(t)
	lesson := map[string]any{
		"id":    "001",
		"title": "Exercise with diag tags",
		"blocks": []any{
			map[string]any{
				"type":         "exercise",
				"exerciseType": "multipleChoice",
				"prompt":       "Pick one",
				"data": map[string]any{
					"options":      []any{"a", "b", "c", "d"},
					"correctIndex": 1,
				},
				"skills":         []any{"vocab.n5", "grammar.particle.wa"},
				"distractorTags": []any{"confusion-a", nil, "confusion-c", "confusion-d"},
			},
		},
	}
	z := buildZip(t, "", map[string]any{
		"manifest.json":    minimalManifestV12(),
		"lessons/001.json": lesson,
	})
	res := v.ValidateZip(z)
	if !res.Ok() {
		t.Fatalf("exercise with skills/distractorTags should validate, got %+v", res.Errors)
	}
}

func TestValidate_V12_ExamModeLesson(t *testing.T) {
	v := newValidator(t)
	lesson := map[string]any{
		"id":           "final-exam",
		"title":        "Pack 1 final",
		"examMode":     true,
		"passingScore": 0.8,
		"timeLimit":    600,
		"drawsFrom":    []any{"001-foundations", "002-people"},
		"blocks": []any{
			map[string]any{
				"type":         "exercise",
				"exerciseType": "multipleChoice",
				"data": map[string]any{
					"options":      []any{"a", "b"},
					"correctIndex": 0,
				},
			},
		},
	}
	m := minimalManifestV12()
	m["lessons"] = []any{
		map[string]any{"id": "final-exam", "file": "lessons/final-exam.json"},
	}
	z := buildZip(t, "", map[string]any{
		"manifest.json":           m,
		"lessons/final-exam.json": lesson,
	})
	res := v.ValidateZip(z)
	if !res.Ok() {
		t.Fatalf("examMode lesson should validate, got %+v", res.Errors)
	}
}

func TestValidate_V12_OldPacksStillWork(t *testing.T) {
	// Belt and braces: with the schema bumped to accept 1.2.0, both 1.0.0 and
	// 1.1.0 packs must keep validating without changes.
	v := newValidator(t)
	for _, name := range []string{"v1.0.0", "v1.1.0"} {
		var m map[string]any
		if name == "v1.0.0" {
			m = minimalManifest()
		} else {
			m = minimalManifestV11()
		}
		z := buildZip(t, "", map[string]any{
			"manifest.json":    m,
			"lessons/001.json": minimalLesson(),
		})
		res := v.ValidateZip(z)
		if !res.Ok() {
			t.Fatalf("legacy %s pack failed under 1.2.0 schema: %+v", name, res.Errors)
		}
	}
}
