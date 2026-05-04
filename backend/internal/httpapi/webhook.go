package httpapi

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/ata/languageapp/backend/internal/db"
	"github.com/ata/languageapp/backend/internal/github"
)

// Cap on the webhook body. GitHub release payloads are typically a few KB;
// 1 MB is generous and prevents log spam from a hostile sender.
const maxWebhookBody = 1 << 20

// githubReleaseEvent is the subset of the release webhook payload we need.
type githubReleaseEvent struct {
	Action     string          `json:"action"`
	Release    *github.Release `json:"release"`
	Repository struct {
		Name     string `json:"name"`
		FullName string `json:"full_name"`
		Owner    struct {
			Login string `json:"login"`
		} `json:"owner"`
	} `json:"repository"`
}

// handleGitHubWebhook validates the signature, parses a release event, and
// triggers ingest under the subscribed user's identity.
//
// Security model:
//   - HMAC-SHA256 with a shared secret (GITHUB_WEBHOOK_SECRET) verifies the body.
//   - Only `release` events with action ∈ {published, released, created} are acted on.
//   - The repo must already be subscribed by some user; otherwise we 404.
func (s *Server) handleGitHubWebhook(w http.ResponseWriter, r *http.Request) {
	if s.webhookSecret == "" {
		writeAPIError(w, http.StatusServiceUnavailable, CodeInternal, "webhooks are not configured")
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, maxWebhookBody+1))
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, CodeBadRequest, "could not read body")
		return
	}
	if len(body) > maxWebhookBody {
		writeAPIError(w, http.StatusRequestEntityTooLarge, CodePayloadTooLarge, "webhook body too large")
		return
	}

	if !verifyGitHubSignature(r.Header.Get("X-Hub-Signature-256"), s.webhookSecret, body) {
		writeAPIError(w, http.StatusUnauthorized, CodeUnauthorized, "invalid signature")
		return
	}

	event := r.Header.Get("X-GitHub-Event")
	if event == "ping" {
		writeJSON(w, http.StatusOK, map[string]string{"pong": "ok"})
		return
	}
	if event != "release" {
		// Acknowledge other events without acting on them so GitHub doesn't retry.
		writeJSON(w, http.StatusOK, map[string]string{"ignored": event})
		return
	}

	var ev githubReleaseEvent
	if err := json.Unmarshal(body, &ev); err != nil {
		writeAPIError(w, http.StatusBadRequest, CodeInvalidJSON, "invalid release payload")
		return
	}
	if !releaseActionTriggersIngest(ev.Action) {
		writeJSON(w, http.StatusOK, map[string]string{"ignored": ev.Action})
		return
	}
	if ev.Release == nil || ev.Repository.Owner.Login == "" || ev.Repository.Name == "" {
		writeAPIError(w, http.StatusBadRequest, CodeBadRequest, "incomplete release payload")
		return
	}

	owner := ev.Repository.Owner.Login
	repo := ev.Repository.Name

	sub, err := s.db.FindWebhookSubscription(r.Context(), owner, repo)
	if err != nil {
		s.logger.Error("find webhook subscription", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "subscription lookup failed")
		return
	}
	if sub == nil {
		writeAPIError(w, http.StatusNotFound, CodeNotFound, "no subscription for this repo")
		return
	}

	asset := github.FindZipAsset(ev.Release, repo)
	if asset == nil {
		writeAPIError(w, http.StatusUnprocessableEntity, CodeBadRequest,
			"release has no .zip asset")
		return
	}

	zipBytes, err := s.github.DownloadAsset(r.Context(), asset, s.maxPackSize)
	if err != nil {
		s.logger.Warn("webhook asset download", "err", err, "repo", owner+"/"+repo)
		writeAPIError(w, http.StatusBadGateway, CodeBadGateway, "could not download release asset")
		return
	}

	out, err := s.ingester.Ingest(r.Context(), zipBytes, "webhook", asset.BrowserURL, sub.UserID)
	if err != nil {
		s.logger.Error("webhook ingest", "err", err, "repo", owner+"/"+repo)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "ingest failed")
		return
	}
	if !out.Validation.Ok() {
		writePackValidationError(w, http.StatusUnprocessableEntity, CodeValidationFailed,
			"pack failed validation", out.Validation)
		return
	}

	action := db.AuditActionUpdate
	if out.IsNewPack {
		action = db.AuditActionPublish
	}
	if err := s.db.InsertAudit(r.Context(), db.AuditInput{
		PackID:    out.Validation.Manifest.ID,
		Version:   out.Validation.Manifest.Version,
		UserID:    sub.UserID,
		Action:    action,
		Source:    "webhook",
		SourceURL: asset.BrowserURL,
		IPAddress: clientIP(r),
		UserAgent: r.UserAgent(),
	}); err != nil {
		s.logger.Warn("audit insert failed", "err", err)
	}

	writeJSON(w, http.StatusAccepted, map[string]any{
		"packId":  out.Validation.Manifest.ID,
		"version": out.Validation.Manifest.Version,
		"action":  action,
	})
}

// verifyGitHubSignature checks the X-Hub-Signature-256 header against an
// HMAC-SHA256 of the body using secret. Header format: "sha256=<hex>".
func verifyGitHubSignature(header, secret string, body []byte) bool {
	const prefix = "sha256="
	if !strings.HasPrefix(header, prefix) {
		return false
	}
	got, err := hex.DecodeString(header[len(prefix):])
	if err != nil {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	want := mac.Sum(nil)
	return hmac.Equal(got, want)
}

func releaseActionTriggersIngest(a string) bool {
	switch a {
	case "published", "released", "created":
		return true
	}
	return false
}

// --- subscription management endpoints (owner-side) ---

type subscribeReq struct {
	RepoURL string `json:"repoUrl"`
}

func (s *Server) handleCreateSubscription(w http.ResponseWriter, r *http.Request) {
	var body subscribeReq
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeAPIError(w, http.StatusBadRequest, CodeInvalidJSON, "invalid JSON body")
		return
	}
	owner, repo, err := github.ParseRepoURL(body.RepoURL)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, CodeBadRequest, "could not parse repo URL",
			FieldError{Path: "repoUrl", Message: err.Error()})
		return
	}
	uid := UserIDFromContext(r.Context())
	sub, err := s.db.CreateWebhookSubscription(r.Context(), uid, owner, repo)
	if errors.Is(err, db.ErrSubscriptionTaken) {
		writeAPIError(w, http.StatusConflict, CodeConflict, "this repo is already subscribed by another user")
		return
	}
	if err != nil {
		s.logger.Error("create subscription", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "could not subscribe")
		return
	}
	writeJSON(w, http.StatusCreated, sub)
}

func (s *Server) handleListSubscriptions(w http.ResponseWriter, r *http.Request) {
	uid := UserIDFromContext(r.Context())
	subs, err := s.db.ListWebhookSubscriptions(r.Context(), uid)
	if err != nil {
		s.logger.Error("list subscriptions", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "could not list")
		return
	}
	if subs == nil {
		subs = []db.WebhookSubscription{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"subscriptions": subs})
}

func (s *Server) handleDeleteSubscription(w http.ResponseWriter, r *http.Request) {
	owner := r.PathValue("owner")
	repo := r.PathValue("repo")
	if owner == "" || repo == "" {
		writeAPIError(w, http.StatusBadRequest, CodeBadRequest, "owner and repo are required")
		return
	}
	uid := UserIDFromContext(r.Context())
	found, err := s.db.DeleteWebhookSubscription(r.Context(), uid, owner, repo)
	if err != nil {
		s.logger.Error("delete subscription", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "could not delete")
		return
	}
	if !found {
		writeAPIError(w, http.StatusNotFound, CodeNotFound, "subscription not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
