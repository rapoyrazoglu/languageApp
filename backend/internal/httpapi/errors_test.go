package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ata/languageapp/backend/internal/pack"
)

func TestWriteAPIError_Shape(t *testing.T) {
	rec := httptest.NewRecorder()
	writeAPIError(rec, http.StatusBadRequest, CodeBadRequest, "nope",
		FieldError{Path: "name", Message: "too short"})

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Fatalf("content-type %q", ct)
	}

	var body errorResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Error.Code != CodeBadRequest || body.Error.Message != "nope" {
		t.Fatalf("unexpected: %+v", body)
	}
	if len(body.Error.Fields) != 1 || body.Error.Fields[0].Path != "name" {
		t.Fatalf("fields not preserved: %+v", body.Error.Fields)
	}
}

func TestWriteAPIError_OmitsEmptyFields(t *testing.T) {
	rec := httptest.NewRecorder()
	writeAPIError(rec, http.StatusInternalServerError, CodeInternal, "boom")

	var raw map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &raw); err != nil {
		t.Fatal(err)
	}
	errObj := raw["error"].(map[string]any)
	if _, has := errObj["fields"]; has {
		t.Fatalf("expected `fields` to be omitted when empty, got %v", errObj)
	}
}

func TestWritePackValidationError_MapsFieldsFromValidation(t *testing.T) {
	vr := &pack.ValidationResult{
		Errors: []pack.ValidationErr{
			{File: "manifest.json", Pointer: "/version", Message: "bad semver"},
			{File: "lessons/001.json", Message: "missing in zip"},
			{Message: "invalid zip"},
		},
	}
	rec := httptest.NewRecorder()
	writePackValidationError(rec, http.StatusUnprocessableEntity, CodeValidationFailed, "validation failed", vr)

	var body errorResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if len(body.Error.Fields) != 3 {
		t.Fatalf("expected 3 fields, got %d", len(body.Error.Fields))
	}
	want := []string{"manifest.json#/version", "lessons/001.json", ""}
	for i, w := range want {
		if body.Error.Fields[i].Path != w {
			t.Errorf("path[%d] = %q, want %q", i, body.Error.Fields[i].Path, w)
		}
	}
}
