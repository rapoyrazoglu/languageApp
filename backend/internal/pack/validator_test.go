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
		"manifest.json":     minimalManifest(),
		"lessons/001.json":  minimalLesson(),
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
		"manifest.json":      minimalManifest(),
		"lessons/001.json":   lesson,
		"media/audio/a.mp3":  []byte{0xff, 0xfb, 0x90, 0x44}, // bogus mp3 bytes — only existence is checked
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
