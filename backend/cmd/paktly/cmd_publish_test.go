package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// Spin up an httptest server that mimics the registry's
// /v1/packs/upload contract; ensure the CLI's upload code sets the right
// auth header, sends a real multipart body, and decodes the success
// response as expected.
func TestUploadToRegistry_SendsAuthAndMultipart(t *testing.T) {
	var capturedAuth string
	var capturedContentType string
	var capturedBody []byte

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedAuth = r.Header.Get("Authorization")
		capturedContentType = r.Header.Get("Content-Type")
		body, _ := io.ReadAll(r.Body)
		capturedBody = body

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"packId":    "com.example.test",
			"version":   "0.1.0",
			"sha256":    "abc",
			"sizeBytes": 4096,
		})
	}))
	defer srv.Close()

	zipBytes := []byte("PK\x03\x04 fake zip bytes")
	result, err := uploadToRegistry(srv.URL, "test-token", "fake.zip", zipBytes)
	if err != nil {
		t.Fatalf("upload: %v", err)
	}
	if result.PackID != "com.example.test" {
		t.Errorf("PackID: want com.example.test, got %q", result.PackID)
	}
	if result.SizeBytes != 4096 {
		t.Errorf("SizeBytes: want 4096, got %d", result.SizeBytes)
	}
	if capturedAuth != "Bearer test-token" {
		t.Errorf("Authorization header: want Bearer test-token, got %q", capturedAuth)
	}
	if !strings.HasPrefix(capturedContentType, "multipart/form-data; boundary=") {
		t.Errorf("Content-Type header: want multipart/form-data; got %q", capturedContentType)
	}
	if !bytes.Contains(capturedBody, zipBytes) {
		t.Errorf("uploaded body missing the zip payload")
	}
	if !bytes.Contains(capturedBody, []byte(`name="pack"`)) {
		t.Errorf("missing form field name=\"pack\"")
	}
}

// Server returns the structured error envelope; the CLI must decode and
// surface it (with code + message + fields) instead of dumping raw HTML.
func TestUploadToRegistry_DecodesStructuredError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnprocessableEntity)
		_, _ = io.WriteString(w, `{"error":{"code":"PACK_VALIDATION_FAILED","message":"manifest invalid","fields":[{"path":"manifest.json#/id","message":"must be reverse-DNS"}]}}`)
	}))
	defer srv.Close()

	_, err := uploadToRegistry(srv.URL, "tok", "fake.zip", []byte("data"))
	if err == nil {
		t.Fatal("expected error")
	}
	cli, ok := err.(*cliError)
	if !ok {
		t.Fatalf("expected *cliError, got %T", err)
	}
	if !strings.Contains(cli.msg, "PACK_VALIDATION_FAILED") {
		t.Errorf("error msg should include code: %q", cli.msg)
	}
	if !strings.Contains(cli.msg, "manifest invalid") {
		t.Errorf("error msg should include message: %q", cli.msg)
	}
	if !strings.Contains(cli.msg, "manifest.json#/id") {
		t.Errorf("error msg should include field path: %q", cli.msg)
	}
}

// 5xx with non-JSON body — the CLI shouldn't crash; it should surface a
// useful "raw HTTP" error so the user sees what the server actually said.
func TestUploadToRegistry_HandlesNonJSONErrorBody(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		_, _ = io.WriteString(w, "<html>nginx 502</html>")
	}))
	defer srv.Close()

	_, err := uploadToRegistry(srv.URL, "tok", "fake.zip", []byte("data"))
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "502") {
		t.Errorf("error should include status: %q", err.Error())
	}
}
