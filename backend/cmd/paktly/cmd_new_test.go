package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/ata/languageapp/backend/internal/pack"
)

// Cover the scaffold end-to-end: render every embedded template into a temp
// directory, then run the result through the registry's validator. This
// prevents template drift — if a future schema bump invalidates what we
// scaffold, the test breaks.
func TestPackNew_ScaffoldedPackPassesValidator(t *testing.T) {
	dir := t.TempDir()
	dest := filepath.Join(dir, "scaffold-test")

	answers := scaffoldAnswers{
		Slug:         "scaffold-test",
		ID:           "com.example.scaffold",
		Name:         "Scaffold Test",
		Description:  "Test scaffolding",
		LanguageCode: "ja",
		UILanguage:   "en",
		Level:        "A1",
		AuthorName:   "Tester",
	}
	answers.applyDefaults()

	if err := writeScaffold(dest, answers); err != nil {
		t.Fatalf("writeScaffold: %v", err)
	}

	// Verify expected files exist.
	for _, rel := range []string{
		"manifest.json",
		"README.md",
		"LICENSE",
		"lessons/001-getting-started.json",
		"media/audio",
		"media/images",
	} {
		full := filepath.Join(dest, rel)
		if _, err := os.Stat(full); err != nil {
			t.Errorf("missing %s: %v", rel, err)
		}
	}

	// Manifest decodes and matches input.
	mfData, err := os.ReadFile(filepath.Join(dest, "manifest.json"))
	if err != nil {
		t.Fatalf("read manifest: %v", err)
	}
	var mf pack.Manifest
	if err := json.Unmarshal(mfData, &mf); err != nil {
		t.Fatalf("decode manifest: %v\nbody: %s", err, mfData)
	}
	if mf.ID != answers.ID {
		t.Errorf("ID: want %q, got %q", answers.ID, mf.ID)
	}
	if mf.Language.Code != answers.LanguageCode {
		t.Errorf("Language.Code: want %q, got %q", answers.LanguageCode, mf.Language.Code)
	}
	if mf.Language.NativeName != answers.LanguageNativeName {
		t.Errorf("Language.NativeName: want %q, got %q", answers.LanguageNativeName, mf.Language.NativeName)
	}
	if mf.SchemaVersion != "1.2.0" {
		t.Errorf("SchemaVersion: want 1.2.0, got %q", mf.SchemaVersion)
	}

	// Zip the directory and run through the validator — same path the
	// real CLI takes from `paktly pack validate <dir>`.
	zipped, err := zipFolder(dest)
	if err != nil {
		t.Fatalf("zipFolder: %v", err)
	}
	v, err := pack.NewValidator()
	if err != nil {
		t.Fatalf("validator init: %v", err)
	}
	res := v.ValidateZip(zipped)
	if !res.Ok() {
		for _, e := range res.Errors {
			t.Errorf("validation error: %s#%s: %s", e.File, e.Pointer, e.Message)
		}
		t.FailNow()
	}
}

func TestSlugPattern_AcceptsValidSlugs(t *testing.T) {
	valid := []string{
		"my-pack",
		"japanese-n5",
		"a1",
		"abc-123",
	}
	for _, s := range valid {
		if !slugPattern.MatchString(s) {
			t.Errorf("expected %q to match", s)
		}
	}
}

func TestSlugPattern_RejectsInvalidSlugs(t *testing.T) {
	invalid := []string{
		"a",             // too short (<2 chars)
		"-leading",      // leading dash
		"With-Capitals", // capital letters
		"under_score",   // underscore
		"with space",    // space
		"./relative",    // path
		"",              // empty
	}
	for _, s := range invalid {
		if slugPattern.MatchString(s) {
			t.Errorf("expected %q to be rejected", s)
		}
	}
}

func TestDefaultID_StripsAndLowercasesAuthor(t *testing.T) {
	got := defaultID(" Ata Poyrazoğlu ", "my-pack")
	want := "com.github.ata-poyrazoğlu.my-pack"
	if got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}

func TestDefaultID_FallsBackWhenAuthorEmpty(t *testing.T) {
	got := defaultID("", "my-pack")
	want := "com.github.creator.my-pack"
	if got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}
