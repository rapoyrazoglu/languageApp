package db

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"time"
)

// SearchOpts is the input to SearchPacks. Empty filters are ignored.
type SearchOpts struct {
	Language string
	Level    string
	Tag      string
	Query    string // free text — matched against name + description
	Limit    int    // clamped to [1, 100]; default 50
	Cursor   string // opaque; pass NextCursor from a previous result
}

// SearchResult is the paginated response.
type SearchResult struct {
	Packs      []Pack `json:"packs"`
	NextCursor string `json:"nextCursor,omitempty"`
	Limit      int    `json:"limit"`
}

// SearchPacks returns packs matching the filters, ordered by updated_at DESC, id DESC.
// Cursor pagination uses the (updated_at, id) tuple as the keyset — stable even
// when new packs are inserted between requests.
func (d *DB) SearchPacks(ctx context.Context, opts SearchOpts) (*SearchResult, error) {
	if opts.Limit <= 0 || opts.Limit > 100 {
		opts.Limit = 50
	}

	var (
		conds []string
		args  []any
	)
	add := func(cond string, val any) {
		args = append(args, val)
		conds = append(conds, fmt.Sprintf(cond, len(args)))
	}

	if opts.Language != "" {
		add("language_code = $%d", opts.Language)
	}
	if opts.Level != "" {
		add("level = $%d", opts.Level)
	}
	if opts.Tag != "" {
		add("$%d = ANY(tags)", opts.Tag)
	}
	if q := strings.TrimSpace(opts.Query); q != "" {
		// Simple ILIKE for now; switch to tsvector if this gets slow.
		args = append(args, q)
		i := len(args)
		conds = append(conds,
			fmt.Sprintf("(name ILIKE '%%' || $%d || '%%' OR description ILIKE '%%' || $%d || '%%')", i, i))
	}

	if opts.Cursor != "" {
		updatedAt, id, err := decodeCursor(opts.Cursor)
		if err != nil {
			return nil, fmt.Errorf("bad cursor: %w", err)
		}
		args = append(args, updatedAt, id)
		conds = append(conds,
			fmt.Sprintf("(updated_at, id) < ($%d, $%d)", len(args)-1, len(args)))
	}

	where := ""
	if len(conds) > 0 {
		where = "WHERE " + strings.Join(conds, " AND ")
	}

	args = append(args, opts.Limit+1) // fetch one extra to detect "more available"
	q := fmt.Sprintf(`
		SELECT id, name, description, language_code, language_name, ui_language, level,
		       author_name, author_url, license, homepage, repository_url, tags,
		       latest_version, created_at, updated_at
		FROM packs
		%s
		ORDER BY updated_at DESC, id DESC
		LIMIT $%d
	`, where, len(args))

	rows, err := d.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]Pack, 0, opts.Limit)
	for rows.Next() {
		var p Pack
		if err := rows.Scan(&p.ID, &p.Name, &p.Description, &p.LanguageCode, &p.LanguageName,
			&p.UILanguage, &p.Level, &p.AuthorName, &p.AuthorURL, &p.License, &p.Homepage,
			&p.RepositoryURL, &p.Tags, &p.LatestVersion, &p.CreatedAt, &p.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	res := &SearchResult{Limit: opts.Limit}
	if len(out) > opts.Limit {
		last := out[opts.Limit-1]
		res.NextCursor = encodeCursor(last.UpdatedAt, last.ID)
		out = out[:opts.Limit]
	}
	res.Packs = out
	return res, nil
}

// Cursor format: base64url("<RFC3339Nano>|<id>"). Opaque to clients.

func encodeCursor(updatedAt time.Time, id string) string {
	raw := updatedAt.UTC().Format(time.RFC3339Nano) + "|" + id
	return base64.RawURLEncoding.EncodeToString([]byte(raw))
}

func decodeCursor(c string) (time.Time, string, error) {
	b, err := base64.RawURLEncoding.DecodeString(c)
	if err != nil {
		return time.Time{}, "", errors.New("not base64url")
	}
	parts := strings.SplitN(string(b), "|", 2)
	if len(parts) != 2 {
		return time.Time{}, "", errors.New("malformed")
	}
	t, err := time.Parse(time.RFC3339Nano, parts[0])
	if err != nil {
		return time.Time{}, "", errors.New("bad timestamp")
	}
	return t, parts[1], nil
}
