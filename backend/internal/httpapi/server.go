package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"

	"github.com/ata/languageapp/backend/internal/auth"
	"github.com/ata/languageapp/backend/internal/db"
	"github.com/ata/languageapp/backend/internal/github"
	"github.com/ata/languageapp/backend/internal/pack"
	"github.com/ata/languageapp/backend/internal/storage"
)

type Server struct {
	logger        *slog.Logger
	mux           *http.ServeMux
	db            *db.DB
	storage       *storage.Client
	ingester      *pack.Ingester
	github        *github.Client
	tokens        *auth.Issuer
	maxPackSize   int64
	limiter       *RateLimiter
	webhookSecret string
}

type Deps struct {
	Logger        *slog.Logger
	DB            *db.DB
	Storage       *storage.Client
	Ingester      *pack.Ingester
	GitHub        *github.Client
	Tokens        *auth.Issuer
	MaxPackSize   int64
	Limiter       *RateLimiter
	WebhookSecret string
}

func NewServer(d Deps) *Server {
	s := &Server{
		logger:        d.Logger,
		mux:           http.NewServeMux(),
		db:            d.DB,
		storage:       d.Storage,
		ingester:      d.Ingester,
		github:        d.GitHub,
		tokens:        d.Tokens,
		maxPackSize:   d.MaxPackSize,
		limiter:       d.Limiter,
		webhookSecret: d.WebhookSecret,
	}
	s.routes()
	return s
}

func (s *Server) routes() {
	s.mux.HandleFunc("GET /healthz", s.handleHealth)

	// Auth (public)
	s.mux.HandleFunc("POST /v1/auth/register", s.handleRegister)
	s.mux.HandleFunc("POST /v1/auth/login", s.handleLogin)
	s.mux.HandleFunc("GET /v1/auth/me", s.requireAuth(s.handleMe))

	// Pack reads (public)
	s.mux.HandleFunc("GET /v1/packs", s.handleListPacks)
	s.mux.HandleFunc("GET /v1/packs/{id}", s.handleGetPack)
	s.mux.HandleFunc("GET /v1/packs/{id}/versions/{version}/download", s.handleDownload)

	// Pack writes (auth required)
	s.mux.HandleFunc("POST /v1/packs/upload", s.requireAuth(s.handleUpload))
	s.mux.HandleFunc("POST /v1/packs/import-github", s.requireAuth(s.handleImportGitHub))

	// Audit log (auth required, owner-only)
	s.mux.HandleFunc("GET /v1/packs/{id}/audit", s.requireAuth(s.handleListAudit))

	// Webhook subscriptions (auth required)
	s.mux.HandleFunc("POST /v1/webhooks/subscriptions", s.requireAuth(s.handleCreateSubscription))
	s.mux.HandleFunc("GET /v1/webhooks/subscriptions", s.requireAuth(s.handleListSubscriptions))
	s.mux.HandleFunc("DELETE /v1/webhooks/subscriptions/{owner}/{repo}", s.requireAuth(s.handleDeleteSubscription))

	// GitHub webhook receiver (signature-verified, no JWT)
	s.mux.HandleFunc("POST /v1/webhooks/github", s.handleGitHubWebhook)
}

func (s *Server) Handler() http.Handler {
	var h http.Handler = s.mux
	if s.limiter != nil {
		h = s.limiter.Wrap(h)
	}
	return logRequests(s.logger, h)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleGetPack(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	p, versions, err := s.db.GetPack(r.Context(), id)
	if err != nil {
		s.logger.Error("get pack", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "lookup failed")
		return
	}
	if p == nil {
		writeAPIError(w, http.StatusNotFound, CodeNotFound, "pack not found")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"pack":     p,
		"versions": versions,
	})
}

func (s *Server) handleDownload(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	version := r.PathValue("version")

	v, err := s.db.GetVersion(r.Context(), id, version)
	if err != nil {
		s.logger.Error("get version", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "lookup failed")
		return
	}
	if v == nil {
		writeAPIError(w, http.StatusNotFound, CodeNotFound, "version not found")
		return
	}

	url, err := s.storage.PresignGet(r.Context(), v.StorageKey, 10*time.Minute)
	if err != nil {
		s.logger.Error("presign", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "presign failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"url":       url,
		"sha256":    v.SHA256,
		"sizeBytes": v.SizeBytes,
		"expiresIn": 600,
	})
}

func (s *Server) handleUpload(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(s.maxPackSize); err != nil {
		writeAPIError(w, http.StatusBadRequest, CodeBadRequest, "could not parse multipart body")
		return
	}
	file, header, err := r.FormFile("pack")
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, CodeMissingField, `missing form field "pack"`,
			FieldError{Path: "pack", Message: "expected multipart file part named 'pack'"})
		return
	}
	defer func() { _ = file.Close() }()

	if header.Size > s.maxPackSize {
		writeAPIError(w, http.StatusRequestEntityTooLarge, CodePayloadTooLarge,
			fmt.Sprintf("pack exceeds %d bytes", s.maxPackSize))
		return
	}

	data, err := io.ReadAll(io.LimitReader(file, s.maxPackSize+1))
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, CodeBadRequest, "could not read upload body")
		return
	}
	if int64(len(data)) > s.maxPackSize {
		writeAPIError(w, http.StatusRequestEntityTooLarge, CodePayloadTooLarge, "pack too large")
		return
	}

	s.ingestAndRespond(w, r, data, "upload", "", UserIDFromContext(r.Context()))
}

func (s *Server) handleImportGitHub(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RepoURL string `json:"repoUrl"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeAPIError(w, http.StatusBadRequest, CodeInvalidJSON, "invalid JSON body")
		return
	}
	if body.RepoURL == "" {
		writeAPIError(w, http.StatusBadRequest, CodeMissingField, `"repoUrl" is required`,
			FieldError{Path: "repoUrl", Message: "must not be empty"})
		return
	}

	owner, repo, err := github.ParseRepoURL(body.RepoURL)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, CodeBadRequest, "could not parse repo URL",
			FieldError{Path: "repoUrl", Message: err.Error()})
		return
	}

	rel, err := s.github.LatestRelease(r.Context(), owner, repo)
	if err != nil {
		s.logger.Warn("github fetch", "err", err)
		writeAPIError(w, http.StatusBadGateway, CodeBadGateway, "could not fetch latest release from GitHub")
		return
	}
	asset := github.FindZipAsset(rel, repo)
	if asset == nil {
		writeAPIError(w, http.StatusUnprocessableEntity, CodeBadRequest,
			"latest release has no .zip asset")
		return
	}

	zipBytes, err := s.github.DownloadAsset(r.Context(), asset, s.maxPackSize)
	if err != nil {
		s.logger.Warn("asset download", "err", err)
		writeAPIError(w, http.StatusBadGateway, CodeBadGateway, "could not download release asset")
		return
	}

	s.ingestAndRespond(w, r, zipBytes, "github", asset.BrowserURL, UserIDFromContext(r.Context()))
}

func (s *Server) ingestAndRespond(w http.ResponseWriter, r *http.Request, data []byte, source, sourceURL, userID string) {
	out, err := s.ingester.Ingest(r.Context(), data, source, sourceURL, userID)
	if errors.Is(err, pack.ErrVersionExists) {
		writePackValidationError(w, http.StatusConflict, CodeVersionExists,
			"this pack id @ version is already published", out.Validation)
		return
	}
	if errors.Is(err, pack.ErrNotPackOwner) {
		writePackValidationError(w, http.StatusForbidden, CodePackOwnerMismatch,
			"this pack id belongs to another user", out.Validation)
		return
	}
	if err != nil {
		s.logger.Error("ingest", "err", err)
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
		UserID:    userID,
		Action:    action,
		Source:    source,
		SourceURL: sourceURL,
		IPAddress: clientIP(r),
		UserAgent: r.UserAgent(),
	}); err != nil {
		// Audit must not block the response; log and move on.
		s.logger.Warn("audit insert failed", "err", err,
			"packId", out.Validation.Manifest.ID, "version", out.Validation.Manifest.Version)
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"packId":     out.Validation.Manifest.ID,
		"version":    out.Validation.Manifest.Version,
		"storageKey": out.StorageKey,
		"sha256":     out.Validation.SHA256,
		"sizeBytes":  out.Validation.Size,
	})
}

func logRequests(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rw, r)
		logger.Info("http",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rw.status,
			"duration_ms", time.Since(start).Milliseconds(),
		)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}
