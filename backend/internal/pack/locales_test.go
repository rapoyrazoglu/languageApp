package pack

import (
	"encoding/json"
	"reflect"
	"testing"
)

// computeCoverage works on raw lesson JSON bodies. These tests synthesize
// minimal lesson docs to exercise the extraction surface deterministically.

func mustEncode(t *testing.T, doc map[string]any) []byte {
	t.Helper()
	b, err := json.Marshal(doc)
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	return b
}

// vocab atom counts for allowlist; example counts for pool only.
func TestCoverage_VocabularyAllowlistVsPool(t *testing.T) {
	lesson := map[string]any{
		"id":    "001",
		"title": "L1",
		"blocks": []any{
			map[string]any{
				"type": "vocabulary",
				"items": []any{
					map[string]any{
						"target":       "私",
						"translations": map[string]any{"tr": "ben", "en": "I"},
						"examples": []any{
							// example translation: pool only, tr-only
							map[string]any{
								"text":         "私は学生です。",
								"translations": map[string]any{"tr": "Ben öğrenciyim."},
							},
						},
					},
					map[string]any{
						"target":       "人",
						"translations": map[string]any{"tr": "kişi", "en": "person"},
					},
				},
			},
		},
	}
	stats := computeCoverage([][]byte{mustEncode(t, lesson)})

	// Allowlist atoms: 2 vocab translations. Both tr+en => both supported (≥90%).
	want := []string{"en", "tr"}
	if !reflect.DeepEqual(stats.SupportedLocales, want) {
		t.Fatalf("SupportedLocales = %v, want %v", stats.SupportedLocales, want)
	}

	// Pool atoms: 2 vocab translations + 1 example translation = 3 total.
	// tr present in all 3 (1.0), en in 2 (~0.6667).
	if got := stats.LocaleCoverage["tr"]; got != 1.0 {
		t.Fatalf("tr coverage = %v, want 1.0", got)
	}
	if got := stats.LocaleCoverage["en"]; got < 0.66 || got > 0.67 {
		t.Fatalf("en coverage = %v, want ~0.6667", got)
	}
}

// dialogue lines + dialogue contexts must NOT count toward the allowlist —
// only the pool-wide percent. A lesson whose only translatable atoms are
// dialogue lines must report zero supported locales.
func TestCoverage_DialogueIsPoolOnly(t *testing.T) {
	lesson := map[string]any{
		"id":    "001",
		"title": "L1",
		"blocks": []any{
			map[string]any{
				"type":     "dialogue",
				"contexts": map[string]any{"tr": "Bir bağlam"},
				"lines": []any{
					map[string]any{
						"target":       "おはよう",
						"translations": map[string]any{"tr": "Günaydın", "en": "Good morning"},
					},
					map[string]any{
						"target":       "こんにちは",
						"translations": map[string]any{"tr": "Merhaba"},
					},
				},
			},
		},
	}
	stats := computeCoverage([][]byte{mustEncode(t, lesson)})

	// Allowlist is empty → no locale clears the threshold.
	if len(stats.SupportedLocales) != 0 {
		t.Fatalf("expected empty SupportedLocales, got %v", stats.SupportedLocales)
	}
	// Pool: context + 2 lines = 3 atoms. tr in all 3 (1.0), en in 1 (0.3333).
	if got := stats.LocaleCoverage["tr"]; got != 1.0 {
		t.Fatalf("tr pool coverage = %v, want 1.0", got)
	}
	if got := stats.LocaleCoverage["en"]; got < 0.33 || got > 0.34 {
		t.Fatalf("en pool coverage = %v, want ~0.3333", got)
	}
}

// kanji.meanings is allowlist; kanji examples and mnemonics are pool-only.
func TestCoverage_KanjiAllowlistOnlyMeaning(t *testing.T) {
	lesson := map[string]any{
		"id":    "001",
		"title": "L1",
		"blocks": []any{
			map[string]any{
				"type": "kanji",
				"items": []any{
					map[string]any{
						"character": "日",
						"meanings":  map[string]any{"tr": "gün", "en": "day"},
						"mnemonics": map[string]any{"tr": "Pencereden güneş"},
						"examples": []any{
							map[string]any{
								"word":         "今日",
								"translations": map[string]any{"tr": "bugün"},
							},
						},
					},
				},
			},
		},
	}
	stats := computeCoverage([][]byte{mustEncode(t, lesson)})
	if !reflect.DeepEqual(stats.SupportedLocales, []string{"en", "tr"}) {
		t.Fatalf("expected en+tr supported (allowlist 100%%), got %v", stats.SupportedLocales)
	}
}

// grammar block contributes 4 allowlist atoms (meanings/formations/usages/
// watchOuts). Examples are pool-only.
func TestCoverage_GrammarFourAllowlistAtoms(t *testing.T) {
	lesson := map[string]any{
		"id":    "001",
		"title": "L1",
		"blocks": []any{
			map[string]any{
				"type":       "grammar",
				"pattern":    "～は～です",
				"meanings":   map[string]any{"tr": "x", "en": "x"},
				"formations": map[string]any{"tr": "y"}, // EN missing here
				"usages":     map[string]any{"tr": "z", "en": "z"},
				"watchOuts":  map[string]any{"tr": "w", "en": "w"},
				"examples": []any{
					map[string]any{
						"text":         "私は学生です。",
						"translations": map[string]any{"tr": "Ben öğrenciyim."},
					},
				},
			},
		},
	}
	stats := computeCoverage([][]byte{mustEncode(t, lesson)})
	// Allowlist atoms = 4. tr in all 4 (1.0). en in 3 (0.75) → below threshold.
	if !reflect.DeepEqual(stats.SupportedLocales, []string{"tr"}) {
		t.Fatalf("expected only tr supported (en at 75%%), got %v", stats.SupportedLocales)
	}
}

// 90% threshold is the cliff. 9/10 atoms in en + 10/10 in tr → both supported.
// 8/10 in en → en falls off.
func TestCoverage_NinetyPercentThreshold(t *testing.T) {
	makeLesson := func(enCount int) []byte {
		items := make([]any, 10)
		for i := 0; i < 10; i++ {
			tr := map[string]any{"tr": "x"}
			if i < enCount {
				tr["en"] = "x"
			}
			items[i] = map[string]any{
				"target":       "w",
				"translations": tr,
			}
		}
		return mustEncode(t, map[string]any{
			"id": "x", "title": "X",
			"blocks": []any{
				map[string]any{"type": "vocabulary", "items": items},
			},
		})
	}

	stats := computeCoverage([][]byte{makeLesson(9)})
	if !reflect.DeepEqual(stats.SupportedLocales, []string{"en", "tr"}) {
		t.Fatalf("9/10 en should clear, got %v", stats.SupportedLocales)
	}

	stats = computeCoverage([][]byte{makeLesson(8)})
	if !reflect.DeepEqual(stats.SupportedLocales, []string{"tr"}) {
		t.Fatalf("8/10 en should NOT clear, got %v", stats.SupportedLocales)
	}
}

// Legacy 1.0/1.1 packs (single `translation` field, no `translations` map)
// produce zero supported locales — we don't know which locale the legacy
// string is in, so we don't credit any.
func TestCoverage_LegacyOnlyVocab_ZeroLocales(t *testing.T) {
	lesson := map[string]any{
		"id":    "001",
		"title": "L1",
		"blocks": []any{
			map[string]any{
				"type": "vocabulary",
				"items": []any{
					map[string]any{
						"target":      "私",
						"translation": "ben",
					},
				},
			},
		},
	}
	stats := computeCoverage([][]byte{mustEncode(t, lesson)})
	if len(stats.SupportedLocales) != 0 {
		t.Fatalf("legacy-only pack should report zero supported locales, got %v", stats.SupportedLocales)
	}
}

// Coverage is integrated with ValidateZip — a happy 1.2.0 pack should produce
// non-empty stats on the result.
func TestValidator_PopulatesCoverageOnSuccess(t *testing.T) {
	v := newValidator(t)
	z := buildZip(t, "", map[string]any{
		"manifest.json":    minimalManifestV12(),
		"lessons/001.json": vocabLessonV12TranslationsMap(),
	})
	res := v.ValidateZip(z)
	if !res.Ok() {
		t.Fatalf("expected valid pack, got errors: %+v", res.Errors)
	}
	// vocabLessonV12TranslationsMap ships one vocab item with 5 locales →
	// all five should clear the 100% threshold of a single-atom allowlist.
	wantLocales := []string{"de", "en", "es", "tr", "zh-Hans"}
	if !reflect.DeepEqual(res.Coverage.SupportedLocales, wantLocales) {
		t.Fatalf("Coverage.SupportedLocales = %v, want %v", res.Coverage.SupportedLocales, wantLocales)
	}
	if got := res.Coverage.LocaleCoverage["tr"]; got != 1.0 {
		t.Fatalf("tr pool coverage = %v, want 1.0", got)
	}
}

// Errors short-circuit coverage — a pack with broken media should report
// nothing rather than misleading numbers.
func TestValidator_NoCoverageOnFailure(t *testing.T) {
	v := newValidator(t)
	lesson := map[string]any{
		"id":    "001",
		"title": "L",
		"blocks": []any{
			map[string]any{
				"type": "vocabulary",
				"items": []any{
					map[string]any{
						"target":       "x",
						"translations": map[string]any{"tr": "x", "en": "x"},
						"audio":        "media/audio/missing.mp3",
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
		t.Fatal("expected media error")
	}
	if len(res.Coverage.SupportedLocales) != 0 || len(res.Coverage.LocaleCoverage) != 0 {
		t.Fatalf("expected coverage zeroed when validation failed, got %+v", res.Coverage)
	}
}

func TestRoundTo(t *testing.T) {
	cases := []struct {
		in   float64
		want float64
	}{
		{0.99641025, 0.9964},
		{0.534, 0.534},
		{0.38765, 0.3877},
		{1.0, 1.0},
		{0.0, 0.0},
	}
	for _, c := range cases {
		if got := roundTo(c.in, 4); got != c.want {
			t.Errorf("roundTo(%v) = %v, want %v", c.in, got, c.want)
		}
	}
}
