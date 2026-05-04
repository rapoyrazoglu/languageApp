package db

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// AuditAction is the verb stored in the log.
const (
	AuditActionPublish = "publish" // first version of a pack
	AuditActionUpdate  = "update"  // subsequent version
)

// AuditEntry is one row in pack_audit_log.
type AuditEntry struct {
	ID        int64     `json:"id"`
	PackID    string    `json:"packId"`
	Version   string    `json:"version"`
	UserID    string    `json:"userId,omitempty"`
	Action    string    `json:"action"`
	Source    string    `json:"source"`
	SourceURL string    `json:"sourceUrl,omitempty"`
	IPAddress string    `json:"ipAddress,omitempty"`
	UserAgent string    `json:"userAgent,omitempty"`
	CreatedAt time.Time `json:"createdAt"`
}

// AuditInput is everything callers pass to InsertAudit.
type AuditInput struct {
	PackID    string
	Version   string
	UserID    string
	Action    string
	Source    string
	SourceURL string
	IPAddress string
	UserAgent string
}

// InsertAudit appends a row. Failures here should never block the request,
// so callers typically log and continue on error.
func (d *DB) InsertAudit(ctx context.Context, in AuditInput) error {
	_, err := d.pool.Exec(ctx, `
		INSERT INTO pack_audit_log
		    (pack_id, version, user_id, action, source, source_url, ip_address, user_agent)
		VALUES ($1, $2, NULLIF($3,'')::uuid, $4, $5, NULLIF($6,''),
		        NULLIF($7,'')::inet, NULLIF($8,''))
	`, in.PackID, in.Version, in.UserID, in.Action, in.Source, in.SourceURL, in.IPAddress, in.UserAgent)
	return err
}

// ListAudit returns the most recent audit rows for a pack, newest first.
func (d *DB) ListAudit(ctx context.Context, packID string, limit int) ([]AuditEntry, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := d.pool.Query(ctx, `
		SELECT id, pack_id, version, COALESCE(user_id::text, ''), action, source,
		       COALESCE(source_url, ''), COALESCE(host(ip_address), ''),
		       COALESCE(user_agent, ''), created_at
		FROM pack_audit_log
		WHERE pack_id = $1
		ORDER BY created_at DESC, id DESC
		LIMIT $2
	`, packID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AuditEntry
	for rows.Next() {
		var e AuditEntry
		if err := rows.Scan(&e.ID, &e.PackID, &e.Version, &e.UserID, &e.Action,
			&e.Source, &e.SourceURL, &e.IPAddress, &e.UserAgent, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// PackExists returns true if a pack row exists. Used by handlers that need
// to distinguish "no audit rows" from "no such pack".
func (d *DB) PackExists(ctx context.Context, packID string) (bool, error) {
	var n int
	err := d.pool.QueryRow(ctx, `SELECT 1 FROM packs WHERE id = $1`, packID).Scan(&n)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}
