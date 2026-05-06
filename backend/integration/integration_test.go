//go:build integration

// Package integration runs end-to-end tests against real Postgres + MinIO.
//
//	make integration-up   # bring up docker-compose
//	make test-integration # run these tests
//
// Required env (defaults match docker-compose.yml):
//
//	INTEGRATION_DATABASE_URL  postgres://langapp:langapp_dev@localhost:5432/langapp?sslmode=disable
//	INTEGRATION_S3_ENDPOINT   http://localhost:9000
//	INTEGRATION_S3_ACCESS_KEY minioadmin
//	INTEGRATION_S3_SECRET_KEY minioadmin
//	INTEGRATION_S3_BUCKET     packs
//
// The test wipes its own data on entry so it can be re-run safely.
package integration

import (
	"archive/zip"
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib" // database/sql driver for goose
	"github.com/pressly/goose/v3"

	"github.com/ata/languageapp/backend/internal/auth"
	"github.com/ata/languageapp/backend/internal/db"
	"github.com/ata/languageapp/backend/internal/httpapi"
	"github.com/ata/languageapp/backend/internal/pack"
	"github.com/ata/languageapp/backend/internal/storage"
)

func slogDiscard() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func defaults() (dbURL, s3Endpoint, s3AK, s3SK, s3Bucket string) {
	return env("INTEGRATION_DATABASE_URL", "postgres://langapp:langapp_dev@localhost:5432/langapp?sslmode=disable"),
		env("INTEGRATION_S3_ENDPOINT", "http://localhost:9000"),
		env("INTEGRATION_S3_ACCESS_KEY", "minioadmin"),
		env("INTEGRATION_S3_SECRET_KEY", "minioadmin"),
		env("INTEGRATION_S3_BUCKET", "packs")
}

// TestEndToEnd_PublishViaUpload covers the full cycle:
//  1. migrations run cleanly,
//  2. user can register + log in,
//  3. an authenticated upload validates + stores + records the pack version,
//  4. the pack appears in search, can be fetched, and yields a presigned URL,
//  5. a publish row appears in the audit log readable by the owner,
//  6. a duplicate version is rejected with VERSION_EXISTS,
//  7. webhook subscription create/list/delete works.
func TestEndToEnd_PublishViaUpload(t *testing.T) {
	dbURL, endpoint, ak, sk, bucket := defaults()
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	// 1. Reset + migrate.
	resetSchema(t, dbURL)
	migrate(t, dbURL)

	// 2. Wire up the same components main.go does.
	database, err := db.Connect(ctx, dbURL)
	if err != nil {
		t.Fatalf("db connect: %v", err)
	}
	t.Cleanup(database.Close)

	store, err := storage.New(ctx, storage.Config{
		Endpoint:     endpoint,
		Region:       "us-east-1",
		Bucket:       bucket,
		AccessKey:    ak,
		SecretKey:    sk,
		UsePathStyle: true,
	})
	if err != nil {
		t.Fatalf("storage: %v", err)
	}

	validator, err := pack.NewValidator()
	if err != nil {
		t.Fatalf("validator: %v", err)
	}
	ingester := &pack.Ingester{
		Validator: validator,
		Storage:   store,
		Sink:      &db.Adapter{DB: database},
	}
	tokens, err := auth.NewIssuer("test-jwt-secret-thats-at-least-32-chars-long", time.Hour)
	if err != nil {
		t.Fatalf("issuer: %v", err)
	}

	srv := httpapi.NewServer(httpapi.Deps{
		Logger:        slogDiscard(),
		DB:            database,
		Storage:       store,
		Ingester:      ingester,
		Tokens:        tokens,
		MaxPackSize:   100 << 20,
		WebhookSecret: "whsec",
	})
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)

	// 3. Register + login.
	tok := registerAndLogin(t, ts.URL, "alice@example.com", "correct horse battery staple")

	// 4. Build a real pack zip from the on-disk example and upload it.
	zipBytes := zipExamplePack(t)
	uploadResp := upload(t, ts.URL, tok, zipBytes)
	if uploadResp["packId"] != "com.github.ata.example-nihongo" {
		t.Fatalf("packId = %v", uploadResp["packId"])
	}
	if uploadResp["version"] != examplePackVersion {
		t.Fatalf("version = %v, want %s", uploadResp["version"], examplePackVersion)
	}

	// 5. List + search.
	list := getJSON(t, ts.URL+"/v1/packs?language=ja", "")
	items, _ := list["packs"].([]any)
	if len(items) != 1 {
		t.Fatalf("expected 1 pack, got %d", len(items))
	}

	getOne := getJSON(t, ts.URL+"/v1/packs/com.github.ata.example-nihongo", "")
	if getOne["pack"] == nil {
		t.Fatalf("get pack: missing pack")
	}

	// 6. Presigned download URL.
	dl := getJSON(t, ts.URL+"/v1/packs/com.github.ata.example-nihongo/versions/"+examplePackVersion+"/download", "")
	url, _ := dl["url"].(string)
	if !strings.HasPrefix(url, "http") {
		t.Fatalf("download url: %q", url)
	}
	resp, err := http.Get(url)
	if err != nil {
		t.Fatalf("presigned GET: %v", err)
	}
	body, _ := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("presigned status %d: %s", resp.StatusCode, string(body))
	}
	if !bytes.Equal(body, zipBytes) {
		t.Fatalf("downloaded bytes don't match upload (%d vs %d)", len(body), len(zipBytes))
	}

	// 7. Audit log: one publish row.
	audit := getJSON(t, ts.URL+"/v1/packs/com.github.ata.example-nihongo/audit", tok)
	entries, _ := audit["entries"].([]any)
	if len(entries) != 1 {
		t.Fatalf("expected 1 audit entry, got %d", len(entries))
	}
	first, _ := entries[0].(map[string]any)
	if first["action"] != "publish" {
		t.Fatalf("audit action = %v, want publish", first["action"])
	}
	if first["source"] != "upload" {
		t.Fatalf("audit source = %v, want upload", first["source"])
	}

	// 8. Re-uploading the same version is a 409 with VERSION_EXISTS.
	dupStatus, dupBody := uploadRaw(t, ts.URL, tok, zipBytes)
	if dupStatus != http.StatusConflict {
		t.Fatalf("dup upload: status %d, body %s", dupStatus, dupBody)
	}
	if !strings.Contains(dupBody, "VERSION_EXISTS") {
		t.Fatalf("dup upload: expected VERSION_EXISTS, got %s", dupBody)
	}

	// 9. Webhook subscription lifecycle.
	subBody, _ := json.Marshal(map[string]string{"repoUrl": "https://github.com/ata/example-nihongo"})
	sub := postJSON(t, ts.URL+"/v1/webhooks/subscriptions", tok, subBody, http.StatusCreated)
	if sub["repoOwner"] != "ata" || sub["repoName"] != "example-nihongo" {
		t.Fatalf("subscription = %v", sub)
	}
	listSubs := getJSON(t, ts.URL+"/v1/webhooks/subscriptions", tok)
	subs, _ := listSubs["subscriptions"].([]any)
	if len(subs) != 1 {
		t.Fatalf("expected 1 subscription, got %d", len(subs))
	}
	delStatus := delete_(t, ts.URL+"/v1/webhooks/subscriptions/ata/example-nihongo", tok)
	if delStatus != http.StatusNoContent {
		t.Fatalf("delete subscription: status %d", delStatus)
	}
}

// --- helpers below ---

func resetSchema(t *testing.T, dbURL string) {
	t.Helper()
	sqlDB, err := sql.Open("pgx", dbURL)
	if err != nil {
		t.Fatalf("sql open: %v", err)
	}
	defer sqlDB.Close()
	stmts := []string{
		`DROP TABLE IF EXISTS pack_audit_log CASCADE`,
		`DROP TABLE IF EXISTS webhook_subscriptions CASCADE`,
		`DROP TABLE IF EXISTS pack_versions CASCADE`,
		`DROP TABLE IF EXISTS packs CASCADE`,
		`DROP TABLE IF EXISTS users CASCADE`,
		`DROP TABLE IF EXISTS goose_db_version CASCADE`,
	}
	for _, s := range stmts {
		if _, err := sqlDB.Exec(s); err != nil {
			t.Fatalf("reset (%s): %v", s, err)
		}
	}
}

func migrate(t *testing.T, dbURL string) {
	t.Helper()
	sqlDB, err := sql.Open("pgx", dbURL)
	if err != nil {
		t.Fatalf("sql open: %v", err)
	}
	defer sqlDB.Close()
	goose.SetBaseFS(nil)
	if err := goose.SetDialect("postgres"); err != nil {
		t.Fatalf("goose dialect: %v", err)
	}
	dir := findMigrationsDir(t)
	if err := goose.Up(sqlDB, dir); err != nil {
		t.Fatalf("goose up: %v", err)
	}
}

func findMigrationsDir(t *testing.T) string {
	t.Helper()
	// Walk up from the test file looking for a `migrations` directory.
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	cur := wd
	for i := 0; i < 6; i++ {
		candidate := filepath.Join(cur, "migrations")
		if info, err := os.Stat(candidate); err == nil && info.IsDir() {
			return candidate
		}
		cur = filepath.Dir(cur)
	}
	t.Fatalf("could not locate migrations dir from %s", wd)
	return ""
}

func zipExamplePack(t *testing.T) []byte {
	t.Helper()
	wd, _ := os.Getwd()
	// The example pack lives at <repo>/packs/example-nihongo.
	root := wd
	for i := 0; i < 6; i++ {
		candidate := filepath.Join(root, "packs", "example-nihongo")
		if info, err := os.Stat(candidate); err == nil && info.IsDir() {
			return zipDir(t, candidate)
		}
		root = filepath.Dir(root)
	}
	t.Fatalf("example-nihongo pack not found from %s", wd)
	return nil
}

// examplePackVersion lazily reads packs/example-nihongo/manifest.json so
// the test doesn't have to be hand-edited every time the example pack
// bumps version.
var examplePackVersion = readExamplePackVersion()

func readExamplePackVersion() string {
	wd, _ := os.Getwd()
	root := wd
	for i := 0; i < 6; i++ {
		manifestPath := filepath.Join(root, "packs", "example-nihongo", "manifest.json")
		if data, err := os.ReadFile(manifestPath); err == nil {
			var m struct {
				Version string `json:"version"`
			}
			if err := json.Unmarshal(data, &m); err == nil && m.Version != "" {
				return m.Version
			}
		}
		root = filepath.Dir(root)
	}
	// Falling back to a known-recent value keeps the package package-level
	// var initialisation safe even if the file walk fails — the test will
	// still report a clear assertion mismatch instead of panicking.
	return "0.0.0"
}

func zipDir(t *testing.T, dir string) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	err := filepath.Walk(dir, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(dir, p)
		if err != nil {
			return err
		}
		f, err := zw.Create(filepath.ToSlash(rel))
		if err != nil {
			return err
		}
		body, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		_, err = f.Write(body)
		return err
	})
	if err != nil {
		t.Fatalf("zip example: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func registerAndLogin(t *testing.T, base, email, password string) string {
	t.Helper()
	body, _ := json.Marshal(map[string]string{"email": email, "password": password})
	resp := postJSON(t, base+"/v1/auth/register", "", body, http.StatusCreated)
	tok, _ := resp["token"].(string)
	if tok == "" {
		t.Fatalf("register returned no token: %v", resp)
	}
	return tok
}

func upload(t *testing.T, base, token string, zipBytes []byte) map[string]any {
	t.Helper()
	status, body := uploadRaw(t, base, token, zipBytes)
	if status != http.StatusCreated {
		t.Fatalf("upload status %d: %s", status, body)
	}
	var out map[string]any
	if err := json.Unmarshal([]byte(body), &out); err != nil {
		t.Fatalf("decode upload: %v", err)
	}
	return out
}

func uploadRaw(t *testing.T, base, token string, zipBytes []byte) (int, string) {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	part, err := mw.CreateFormFile("pack", "pack.zip")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := part.Write(zipBytes); err != nil {
		t.Fatal(err)
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/packs/upload", &buf)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("upload do: %v", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(body)
}

func getJSON(t *testing.T, url, token string) map[string]any {
	t.Helper()
	req, _ := http.NewRequest(http.MethodGet, url, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("get %s: %v", url, err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode/100 != 2 {
		t.Fatalf("get %s status %d: %s", url, resp.StatusCode, string(body))
	}
	var out map[string]any
	if err := json.Unmarshal(body, &out); err != nil {
		t.Fatalf("decode %s: %v\nbody=%s", url, err, string(body))
	}
	return out
}

func postJSON(t *testing.T, url, token string, body []byte, expect int) map[string]any {
	t.Helper()
	req, _ := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("post %s: %v", url, err)
	}
	defer resp.Body.Close()
	rb, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != expect {
		t.Fatalf("post %s status %d (want %d): %s", url, resp.StatusCode, expect, string(rb))
	}
	if len(rb) == 0 {
		return nil
	}
	var out map[string]any
	if err := json.Unmarshal(rb, &out); err != nil {
		t.Fatalf("decode %s: %v\nbody=%s", url, err, string(rb))
	}
	return out
}

func delete_(t *testing.T, url, token string) int {
	t.Helper()
	req, _ := http.NewRequest(http.MethodDelete, url, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("delete %s: %v", url, err)
	}
	_, _ = io.ReadAll(resp.Body)
	resp.Body.Close()
	return resp.StatusCode
}
