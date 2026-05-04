package db

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// WebhookSubscription maps a GitHub repo to a user. When a release event
// arrives for that repo, ingest runs under this user's identity.
type WebhookSubscription struct {
	ID        string    `json:"id"`
	UserID    string    `json:"userId"`
	RepoOwner string    `json:"repoOwner"`
	RepoName  string    `json:"repoName"`
	CreatedAt time.Time `json:"createdAt"`
}

var ErrSubscriptionTaken = errors.New("repo already subscribed by another user")

// CreateWebhookSubscription registers (owner/repo) → user. Idempotent for the
// same user, but returns ErrSubscriptionTaken if another user has the repo.
func (d *DB) CreateWebhookSubscription(ctx context.Context, userID, owner, repo string) (*WebhookSubscription, error) {
	tx, err := d.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	var existing string
	err = tx.QueryRow(ctx, `
		SELECT user_id::text FROM webhook_subscriptions
		WHERE repo_owner = $1 AND repo_name = $2
		FOR UPDATE
	`, owner, repo).Scan(&existing)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}
	if existing != "" && existing != userID {
		return nil, ErrSubscriptionTaken
	}

	var sub WebhookSubscription
	if existing == "" {
		err = tx.QueryRow(ctx, `
			INSERT INTO webhook_subscriptions (user_id, repo_owner, repo_name)
			VALUES ($1::uuid, $2, $3)
			RETURNING id::text, user_id::text, repo_owner, repo_name, created_at
		`, userID, owner, repo).Scan(&sub.ID, &sub.UserID, &sub.RepoOwner, &sub.RepoName, &sub.CreatedAt)
	} else {
		err = tx.QueryRow(ctx, `
			SELECT id::text, user_id::text, repo_owner, repo_name, created_at
			FROM webhook_subscriptions
			WHERE repo_owner = $1 AND repo_name = $2
		`, owner, repo).Scan(&sub.ID, &sub.UserID, &sub.RepoOwner, &sub.RepoName, &sub.CreatedAt)
	}
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &sub, nil
}

// FindWebhookSubscription returns the subscription that owns (owner/repo), if any.
func (d *DB) FindWebhookSubscription(ctx context.Context, owner, repo string) (*WebhookSubscription, error) {
	var sub WebhookSubscription
	err := d.pool.QueryRow(ctx, `
		SELECT id::text, user_id::text, repo_owner, repo_name, created_at
		FROM webhook_subscriptions
		WHERE repo_owner = $1 AND repo_name = $2
	`, owner, repo).Scan(&sub.ID, &sub.UserID, &sub.RepoOwner, &sub.RepoName, &sub.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &sub, nil
}

// ListWebhookSubscriptions returns every subscription for a user, newest first.
func (d *DB) ListWebhookSubscriptions(ctx context.Context, userID string) ([]WebhookSubscription, error) {
	rows, err := d.pool.Query(ctx, `
		SELECT id::text, user_id::text, repo_owner, repo_name, created_at
		FROM webhook_subscriptions
		WHERE user_id = $1::uuid
		ORDER BY created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []WebhookSubscription
	for rows.Next() {
		var s WebhookSubscription
		if err := rows.Scan(&s.ID, &s.UserID, &s.RepoOwner, &s.RepoName, &s.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// DeleteWebhookSubscription removes a subscription belonging to userID. Returns
// (found, error). found=false means no row matched (could be missing or owned by another user).
func (d *DB) DeleteWebhookSubscription(ctx context.Context, userID, owner, repo string) (bool, error) {
	tag, err := d.pool.Exec(ctx, `
		DELETE FROM webhook_subscriptions
		WHERE user_id = $1::uuid AND repo_owner = $2 AND repo_name = $3
	`, userID, owner, repo)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}
