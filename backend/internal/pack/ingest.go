package pack

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/ata/languageapp/backend/internal/storage"
)

// Sink is the persistence layer the ingester writes to.
// Defined here to avoid an import cycle with `db`.
type Sink interface {
	UpsertPackAndVersion(ctx context.Context, in SinkInput) (SinkResult, error)
}

type SinkInput struct {
	Manifest    *Manifest
	ManifestRaw []byte
	SHA256      string
	SizeBytes   int64
	StorageKey  string
	Source      string
	SourceURL   string
	UserID      string

	// Coverage signals derived from lesson content — see
	// pack.CoverageStats. Empty/zero on packs that validated under 1.0.0 /
	// 1.1.0 schema and didn't ship multi-locale `translations` maps.
	SupportedLocales []string
	LocaleCoverage   map[string]float64
}

// SinkResult tells the ingester whether this was the very first version
// for a pack id (publish) or a subsequent one (update).
type SinkResult struct {
	IsNewPack bool
}

var (
	ErrVersionExists = errors.New("pack version already exists")
	ErrNotPackOwner  = errors.New("user is not the owner of this pack")
)

// Ingester runs validate → upload → record for a zip blob.
type Ingester struct {
	Validator *Validator
	Storage   *storage.Client
	Sink      Sink
}

type IngestResult struct {
	Validation *ValidationResult `json:"validation"`
	StorageKey string            `json:"storageKey,omitempty"`
	IsNewPack  bool              `json:"-"` // first version for this id?
}

func (in *Ingester) Ingest(ctx context.Context, zipBytes []byte, source, sourceURL, userID string) (*IngestResult, error) {
	res := in.Validator.ValidateZip(zipBytes)
	out := &IngestResult{Validation: res}
	if !res.Ok() {
		return out, nil
	}

	m := res.Manifest
	key := storage.PackKey(m.ID, m.Version)

	if err := in.Storage.Put(ctx, key, zipBytes, "application/zip"); err != nil {
		return out, fmt.Errorf("storage put: %w", err)
	}
	out.StorageKey = key

	manifestRaw, _ := json.Marshal(m)

	sinkRes, err := in.Sink.UpsertPackAndVersion(ctx, SinkInput{
		Manifest:         m,
		ManifestRaw:      manifestRaw,
		SHA256:           res.SHA256,
		SizeBytes:        res.Size,
		StorageKey:       key,
		Source:           source,
		SourceURL:        sourceURL,
		UserID:           userID,
		SupportedLocales: res.Coverage.SupportedLocales,
		LocaleCoverage:   res.Coverage.LocaleCoverage,
	})
	if err != nil {
		return out, err
	}
	out.IsNewPack = sinkRes.IsNewPack
	return out, nil
}
