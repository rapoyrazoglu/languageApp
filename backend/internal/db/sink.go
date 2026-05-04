package db

import (
	"context"
	"errors"

	"github.com/ata/languageapp/backend/internal/pack"
)

// Adapter exposes DB through the pack.Sink interface so the ingester
// doesn't depend on the db package directly.
type Adapter struct{ DB *DB }

func (a *Adapter) UpsertPackAndVersion(ctx context.Context, in pack.SinkInput) error {
	err := a.DB.UpsertPackAndVersion(ctx, UpsertPackInput{
		Manifest:    in.Manifest,
		ManifestRaw: in.ManifestRaw,
		SHA256:      in.SHA256,
		SizeBytes:   in.SizeBytes,
		StorageKey:  in.StorageKey,
		Source:      in.Source,
		SourceURL:   in.SourceURL,
		UserID:      in.UserID,
	})
	switch {
	case errors.Is(err, ErrVersionExists):
		return pack.ErrVersionExists
	case errors.Is(err, ErrNotPackOwner):
		return pack.ErrNotPackOwner
	}
	return err
}
