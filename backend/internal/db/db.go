package db

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/ata/languageapp/backend/internal/pack"
)

type DB struct {
	pool *pgxpool.Pool
}

func Connect(ctx context.Context, url string) (*DB, error) {
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping: %w", err)
	}
	return &DB{pool: pool}, nil
}

func (d *DB) Close() { d.pool.Close() }

// Pack is the row in the `packs` table.
type Pack struct {
	ID            string    `json:"id"`
	Name          string    `json:"name"`
	Description   string    `json:"description,omitempty"`
	LanguageCode  string    `json:"languageCode"`
	LanguageName  string    `json:"languageName"`
	UILanguage    string    `json:"uiLanguage,omitempty"`
	Level         string    `json:"level,omitempty"`
	AuthorName    string    `json:"authorName"`
	AuthorURL     string    `json:"authorUrl,omitempty"`
	License       string    `json:"license"`
	Homepage      string    `json:"homepage,omitempty"`
	RepositoryURL string    `json:"repositoryUrl,omitempty"`
	Tags          []string  `json:"tags"`
	LatestVersion string    `json:"latestVersion,omitempty"`
	CreatedAt     time.Time `json:"createdAt"`
	UpdatedAt     time.Time `json:"updatedAt"`
}

// PackVersion is the row in `pack_versions`.
type PackVersion struct {
	PackID        string          `json:"packId"`
	Version       string          `json:"version"`
	SchemaVersion string          `json:"schemaVersion"`
	SHA256        string          `json:"sha256"`
	SizeBytes     int64           `json:"sizeBytes"`
	StorageKey    string          `json:"storageKey"`
	Source        string          `json:"source"`
	SourceURL     string          `json:"sourceUrl,omitempty"`
	ManifestJSON  json.RawMessage `json:"manifest"`
	MinSDKVersion string          `json:"minSdkVersion,omitempty"`
	CreatedAt     time.Time       `json:"createdAt"`

	// Locale signals (schema 1.2.0+). Empty/zero on legacy packs.
	SupportedLocales  []string           `json:"supportedLocales"`
	LocaleCoverage    map[string]float64 `json:"localeCoverage"`
	TranslationStatus map[string]string  `json:"translationStatus,omitempty"`
}

// UpsertPackInput captures everything needed to insert/update both rows in a single tx.
type UpsertPackInput struct {
	Manifest    *pack.Manifest
	ManifestRaw []byte
	SHA256      string
	SizeBytes   int64
	StorageKey  string
	Source      string // "github" | "upload"
	SourceURL   string
	UserID      string // uploader; becomes owner if pack is new

	// Locale signals derived by the validator. Persist on the version row;
	// a nil/empty SupportedLocales means "no multi-locale data" and stays
	// `'{}'::text[]` in the column thanks to the migration default.
	SupportedLocales []string
	LocaleCoverage   map[string]float64
}

var (
	ErrVersionExists = errors.New("pack version already exists")
	ErrNotPackOwner  = errors.New("user is not the owner of this pack")
)

// PackOwner returns the owner_user_id for a pack, or empty string if pack
// doesn't exist or has no owner. Useful for the ingester to enforce ownership.
func (d *DB) PackOwner(ctx context.Context, packID string) (string, error) {
	var owner *string
	err := d.pool.QueryRow(ctx, `SELECT owner_user_id::text FROM packs WHERE id = $1`, packID).Scan(&owner)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	if owner == nil {
		return "", nil
	}
	return *owner, nil
}

// UpsertResult tells callers whether the pack id existed before this call.
// IsNewPack is true when the upsert created a brand-new packs row.
type UpsertResult struct {
	IsNewPack bool
}

// UpsertPackAndVersion upserts the pack row and inserts a new version row.
// Returns ErrVersionExists if (pack_id, version) already exists.
// Returns ErrNotPackOwner if the pack already exists with a different owner.
func (d *DB) UpsertPackAndVersion(ctx context.Context, in UpsertPackInput) (UpsertResult, error) {
	m := in.Manifest

	if in.UserID == "" {
		return UpsertResult{}, errors.New("UserID is required")
	}

	tx, err := d.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return UpsertResult{}, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	// Lock the pack row (if any) so a concurrent uploader can't race ownership.
	var existingOwner *string
	err = tx.QueryRow(ctx, `SELECT owner_user_id::text FROM packs WHERE id = $1 FOR UPDATE`, m.ID).Scan(&existingOwner)
	isNew := errors.Is(err, pgx.ErrNoRows)
	if err != nil && !isNew {
		return UpsertResult{}, fmt.Errorf("lock pack: %w", err)
	}
	if existingOwner != nil && *existingOwner != in.UserID {
		return UpsertResult{}, ErrNotPackOwner
	}

	repoURL := ""
	if m.Repository != nil {
		repoURL = m.Repository.URL
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO packs (
			id, name, description, language_code, language_name, ui_language, level,
			author_name, author_url, license, homepage, repository_url, tags, latest_version,
			owner_user_id
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
		ON CONFLICT (id) DO UPDATE SET
			name           = EXCLUDED.name,
			description    = EXCLUDED.description,
			language_code  = EXCLUDED.language_code,
			language_name  = EXCLUDED.language_name,
			ui_language    = EXCLUDED.ui_language,
			level          = EXCLUDED.level,
			author_name    = EXCLUDED.author_name,
			author_url     = EXCLUDED.author_url,
			license        = EXCLUDED.license,
			homepage       = EXCLUDED.homepage,
			repository_url = EXCLUDED.repository_url,
			tags           = EXCLUDED.tags,
			latest_version = EXCLUDED.latest_version,
			updated_at     = now()
		-- owner_user_id is NEVER overwritten by the upsert path; ownership is sticky.
	`, m.ID, m.Name, m.Description, m.Language.Code, m.Language.Name, m.UILanguage, m.Level,
		m.Author.Name, m.Author.URL, m.License, m.Homepage, repoURL, m.Tags, m.Version,
		in.UserID)
	if err != nil {
		return UpsertResult{}, fmt.Errorf("upsert pack: %w", err)
	}

	// Coverage maps default to '{}' in the column when nil; we still pass an
	// explicit JSON `{}` to keep the queries grep-able.
	coverageJSON, err := json.Marshal(orEmptyMap(in.LocaleCoverage))
	if err != nil {
		return UpsertResult{}, fmt.Errorf("marshal locale_coverage: %w", err)
	}
	translationStatusJSON, err := json.Marshal(orEmptyStringMap(m.TranslationStatus))
	if err != nil {
		return UpsertResult{}, fmt.Errorf("marshal translation_status: %w", err)
	}
	supported := in.SupportedLocales
	if supported == nil {
		supported = []string{}
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO pack_versions (
			pack_id, version, schema_version, sha256, size_bytes, storage_key,
			source, source_url, manifest_json, min_sdk_version, uploader_user_id,
			supported_locales, locale_coverage, translation_status
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
	`, m.ID, m.Version, m.SchemaVersion, in.SHA256, in.SizeBytes, in.StorageKey,
		in.Source, in.SourceURL, in.ManifestRaw, m.MinSDKVersion, in.UserID,
		supported, coverageJSON, translationStatusJSON)
	if err != nil {
		if isUniqueViolation(err) {
			return UpsertResult{}, ErrVersionExists
		}
		return UpsertResult{}, fmt.Errorf("insert version: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return UpsertResult{}, err
	}
	return UpsertResult{IsNewPack: isNew}, nil
}

func isUniqueViolation(err error) bool {
	var pgErr interface{ SQLState() string }
	return errors.As(err, &pgErr) && pgErr.SQLState() == "23505"
}

// Helper shims so JSON marshal of locale-coverage / translation-status maps
// always produces `{}` rather than `null` — keeps the column predictable
// for downstream readers.

func orEmptyMap(m map[string]float64) map[string]float64 {
	if m == nil {
		return map[string]float64{}
	}
	return m
}

func orEmptyStringMap(m map[string]string) map[string]string {
	if m == nil {
		return map[string]string{}
	}
	return m
}

func (d *DB) ListPacks(ctx context.Context, languageCode string, limit int) ([]Pack, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := d.pool.Query(ctx, `
		SELECT id, name, description, language_code, language_name, ui_language, level,
		       author_name, author_url, license, homepage, repository_url, tags,
		       latest_version, created_at, updated_at
		FROM packs
		WHERE ($1 = '' OR language_code = $1)
		ORDER BY updated_at DESC
		LIMIT $2
	`, languageCode, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Pack
	for rows.Next() {
		var p Pack
		if err := rows.Scan(&p.ID, &p.Name, &p.Description, &p.LanguageCode, &p.LanguageName,
			&p.UILanguage, &p.Level, &p.AuthorName, &p.AuthorURL, &p.License, &p.Homepage,
			&p.RepositoryURL, &p.Tags, &p.LatestVersion, &p.CreatedAt, &p.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (d *DB) GetPack(ctx context.Context, id string) (*Pack, []PackVersion, error) {
	var p Pack
	err := d.pool.QueryRow(ctx, `
		SELECT id, name, description, language_code, language_name, ui_language, level,
		       author_name, author_url, license, homepage, repository_url, tags,
		       latest_version, created_at, updated_at
		FROM packs WHERE id = $1
	`, id).Scan(&p.ID, &p.Name, &p.Description, &p.LanguageCode, &p.LanguageName,
		&p.UILanguage, &p.Level, &p.AuthorName, &p.AuthorURL, &p.License, &p.Homepage,
		&p.RepositoryURL, &p.Tags, &p.LatestVersion, &p.CreatedAt, &p.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil, nil
	}
	if err != nil {
		return nil, nil, err
	}

	rows, err := d.pool.Query(ctx, `
		SELECT pack_id, version, schema_version, sha256, size_bytes, storage_key,
		       source, source_url, manifest_json, min_sdk_version, created_at,
		       supported_locales, locale_coverage, translation_status
		FROM pack_versions WHERE pack_id = $1
		ORDER BY created_at DESC
	`, id)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	var versions []PackVersion
	for rows.Next() {
		v, err := scanPackVersion(rows)
		if err != nil {
			return nil, nil, err
		}
		versions = append(versions, v)
	}
	return &p, versions, rows.Err()
}

// scanPackVersion decodes a pack_versions row that selected the full column
// list (including the locale signals introduced in migration 00004).
//
// Postgres returns JSONB columns as []byte; we json-Unmarshal into typed
// maps so callers don't have to think about the wire format.
func scanPackVersion(row interface {
	Scan(...any) error
}) (PackVersion, error) {
	var v PackVersion
	var coverageRaw, translationStatusRaw []byte
	err := row.Scan(&v.PackID, &v.Version, &v.SchemaVersion, &v.SHA256, &v.SizeBytes,
		&v.StorageKey, &v.Source, &v.SourceURL, &v.ManifestJSON, &v.MinSDKVersion, &v.CreatedAt,
		&v.SupportedLocales, &coverageRaw, &translationStatusRaw)
	if err != nil {
		return PackVersion{}, err
	}
	if v.SupportedLocales == nil {
		v.SupportedLocales = []string{}
	}
	if len(coverageRaw) > 0 {
		if err := json.Unmarshal(coverageRaw, &v.LocaleCoverage); err != nil {
			return PackVersion{}, fmt.Errorf("decode locale_coverage: %w", err)
		}
	}
	if v.LocaleCoverage == nil {
		v.LocaleCoverage = map[string]float64{}
	}
	if len(translationStatusRaw) > 0 {
		if err := json.Unmarshal(translationStatusRaw, &v.TranslationStatus); err != nil {
			return PackVersion{}, fmt.Errorf("decode translation_status: %w", err)
		}
	}
	return v, nil
}

func (d *DB) GetVersion(ctx context.Context, packID, version string) (*PackVersion, error) {
	row := d.pool.QueryRow(ctx, `
		SELECT pack_id, version, schema_version, sha256, size_bytes, storage_key,
		       source, source_url, manifest_json, min_sdk_version, created_at,
		       supported_locales, locale_coverage, translation_status
		FROM pack_versions WHERE pack_id = $1 AND version = $2
	`, packID, version)
	v, err := scanPackVersion(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &v, nil
}
