package pack

import (
	"encoding/json"
	"sort"
)

// Locale-coverage extraction (schema 1.2.0+)
//
// Two signals come out of every lesson the validator parses:
//
//   1. supportedLocales — atom-kind allowlist, ≥90% threshold. Drives the
//      Discover "For X speakers" filter. Sayılan atomlar:
//        - vocabulary.items[].translations
//        - kanji.items[].meanings
//        - grammar.meanings / formations / usages / watchOuts
//      Sayılmayan: vocabulary examples, dialogue lines, dialogue contexts,
//      kanji examples, kanji mnemonics, grammar examples.
//
//   2. localeCoverage — pool-wide percent map across **every** translatable
//      atom in the pack (allowlist + the rest). Surfaced in the UI as a
//      transparency chip so users can see "EN: 53%" before downloading a
//      pack whose core is multi-locale but examples are TR-only.
//
// Both maps are computed during validation and persisted on `pack_versions`.

// SupportedLocaleThreshold is the fraction of allowlist atoms that must
// carry a string in a given locale for that locale to count as "supported".
const SupportedLocaleThreshold = 0.90

// CoverageStats aggregates the two signals.
type CoverageStats struct {
	// SupportedLocales — sorted, distinct locale codes that cleared the
	// allowlist threshold.
	SupportedLocales []string `json:"supportedLocales"`
	// LocaleCoverage — percent (0..1) of pool-wide atoms each locale covers,
	// rounded to 4 decimal places. Includes locales below the support
	// threshold so the UI can show an honest coverage chip.
	LocaleCoverage map[string]float64 `json:"localeCoverage"`
}

// computeCoverage walks every lesson body and tallies translation keys.
// `lessonBodies` is the raw JSON of each lesson; the function decodes only
// the fields it needs and is tolerant of unrelated fields. Lesson bodies
// that fail to parse are skipped (the validator has already flagged them
// via the schema check; this layer only runs on lessons that passed).
func computeCoverage(lessonBodies [][]byte) CoverageStats {
	tally := newCoverageTally()
	for _, body := range lessonBodies {
		var lesson localeLesson
		if err := json.Unmarshal(body, &lesson); err != nil {
			continue
		}
		for _, b := range lesson.Blocks {
			b.tally(tally)
		}
	}
	return tally.snapshot()
}

// localeLesson mirrors only the fields the coverage walker reads. Keeping
// this separate from the validator's `lessonBlock` keeps the two concerns
// decoupled — the validator cares about media references, this code cares
// about translation keys.
type localeLesson struct {
	Blocks []localeBlock `json:"blocks"`
}

type localeBlock struct {
	Type string `json:"type"`

	// vocabulary.items + kanji.items
	Items []localeItem `json:"items,omitempty"`

	// dialogue.lines + dialogue.contexts
	Lines    []localeLine      `json:"lines,omitempty"`
	Contexts map[string]string `json:"contexts,omitempty"`
	Context  string            `json:"context,omitempty"`

	// grammar block — top-level fields
	Pattern    string            `json:"pattern,omitempty"`
	Meaning    string            `json:"meaning,omitempty"`
	Meanings   map[string]string `json:"meanings,omitempty"`
	Formation  string            `json:"formation,omitempty"`
	Formations map[string]string `json:"formations,omitempty"`
	Usage      string            `json:"usage,omitempty"`
	Usages     map[string]string `json:"usages,omitempty"`
	WatchOut   string            `json:"watchOut,omitempty"`
	WatchOuts  map[string]string `json:"watchOuts,omitempty"`
	Examples   []localeExample   `json:"examples,omitempty"`
}

// localeItem is the union of `vocabulary.items[]` and `kanji.items[]` —
// they overlap on the fields coverage cares about. The disambiguator is
// the parent block's `type`, threaded through `tally`.
type localeItem struct {
	// vocabulary
	Translation  string            `json:"translation,omitempty"`
	Translations map[string]string `json:"translations,omitempty"`
	Examples     []localeExample   `json:"examples,omitempty"`

	// kanji
	Meaning   string            `json:"meaning,omitempty"`
	Meanings  map[string]string `json:"meanings,omitempty"`
	Mnemonic  string            `json:"mnemonic,omitempty"`
	Mnemonics map[string]string `json:"mnemonics,omitempty"`
}

type localeLine struct {
	Translation  string            `json:"translation,omitempty"`
	Translations map[string]string `json:"translations,omitempty"`
}

type localeExample struct {
	Translation  string            `json:"translation,omitempty"`
	Translations map[string]string `json:"translations,omitempty"`
}

// tally walks one block, counting one `allowlistAtom` per allowlist string
// and one `poolAtom` per any-translatable string. Each atom records which
// locale keys are present.
func (b localeBlock) tally(t *coverageTally) {
	switch b.Type {
	case "vocabulary":
		for _, it := range b.Items {
			t.add(allowlistAtom, it.Translation, it.Translations)
			for _, ex := range it.Examples {
				t.add(poolOnly, ex.Translation, ex.Translations)
			}
		}
	case "kanji":
		for _, it := range b.Items {
			t.add(allowlistAtom, it.Meaning, it.Meanings)
			t.add(poolOnly, it.Mnemonic, it.Mnemonics)
			for _, ex := range it.Examples {
				t.add(poolOnly, ex.Translation, ex.Translations)
			}
		}
	case "dialogue":
		t.add(poolOnly, b.Context, b.Contexts)
		for _, ln := range b.Lines {
			t.add(poolOnly, ln.Translation, ln.Translations)
		}
	case "grammar":
		// All four core grammar fields are allowlist atoms — they're the
		// pattern's core teaching content.
		t.add(allowlistAtom, b.Meaning, b.Meanings)
		t.add(allowlistAtom, b.Formation, b.Formations)
		t.add(allowlistAtom, b.Usage, b.Usages)
		t.add(allowlistAtom, b.WatchOut, b.WatchOuts)
		for _, ex := range b.Examples {
			t.add(poolOnly, ex.Translation, ex.Translations)
		}
	}
}

// atomKind says whether this string contributes to the supportedLocales
// allowlist (atom-kind allowlist) plus the pool, or only the pool.
type atomKind int

const (
	allowlistAtom atomKind = iota // counted in both allowlist + pool
	poolOnly                      // counted only in the pool-wide coverage
)

// coverageTally accumulates locale presence across every atom in a pack.
// Each atom contributes once to `total*` and once to `present*[locale]`
// for each locale that has a string for it.
type coverageTally struct {
	totalAllowlist int
	totalPool      int
	presentList    map[string]int
	presentPool    map[string]int
}

func newCoverageTally() *coverageTally {
	return &coverageTally{
		presentList: map[string]int{},
		presentPool: map[string]int{},
	}
}

// add records one translatable atom. `legacy` is the single-locale value
// (1.0.0/1.1.0 packs); `m` is the multi-locale map (1.2.0+). An atom
// counts in `present*[locale]` for each map key plus, if `legacy` is non-
// empty and the pack declares `manifest.uiLanguage`, that uiLanguage.
//
// Note: the caller doesn't have access to manifest.uiLanguage here, so
// legacy strings are NOT auto-credited to a locale. This is intentional —
// 1.0.0/1.1.0 packs that only ship a single `translation` will report 0
// supported locales, which is the right answer: we don't know which locale
// the string is in. A 1.2.0+ pack that wants the legacy field credited
// should also emit `translations: {"<locale>": "..."}`.
func (t *coverageTally) add(kind atomKind, legacy string, m map[string]string) {
	if legacy == "" && len(m) == 0 {
		return // not a translatable atom
	}
	if kind == allowlistAtom {
		t.totalAllowlist++
	}
	t.totalPool++
	for locale, value := range m {
		if value == "" {
			continue
		}
		if kind == allowlistAtom {
			t.presentList[locale]++
		}
		t.presentPool[locale]++
	}
}

func (t *coverageTally) snapshot() CoverageStats {
	stats := CoverageStats{
		SupportedLocales: []string{},
		LocaleCoverage:   map[string]float64{},
	}
	if t.totalAllowlist > 0 {
		for locale, n := range t.presentList {
			frac := float64(n) / float64(t.totalAllowlist)
			if frac >= SupportedLocaleThreshold {
				stats.SupportedLocales = append(stats.SupportedLocales, locale)
			}
		}
		sort.Strings(stats.SupportedLocales)
	}
	if t.totalPool > 0 {
		for locale, n := range t.presentPool {
			stats.LocaleCoverage[locale] = roundTo(float64(n)/float64(t.totalPool), 4)
		}
	}
	return stats
}

// roundTo rounds f to `places` decimals. Pure helper so coverage values
// don't carry float drift through JSON serialisation.
func roundTo(f float64, places int) float64 {
	scale := 1.0
	for i := 0; i < places; i++ {
		scale *= 10
	}
	return float64(int64(f*scale+0.5)) / scale
}
