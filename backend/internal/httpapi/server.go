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
	logger      *slog.Logger
	mux         *http.ServeMux
	db          *db.DB
	storage     *storage.Client
	ingester    *pack.Ingester
	github      *github.Client
	tokens      *auth.Issuer
	maxPackSize int64
}

type Deps struct {
	Logger      *slog.Logger
	DB          *db.DB
	Storage     *storage.Client
	Ingester    *pack.Ingester
	GitHub      *github.Client
	Tokens      *auth.Issuer
	MaxPackSize int64
}

func NewServer(d Deps) *Server {
	s := &Server{
		logger:      d.Logger,
		mux:         http.NewServeMux(),
		db:          d.DB,
		storage:     d.Storage,
		ingester:    d.Ingester,
		github:      d.GitHub,
		tokens:      d.Tokens,
		maxPackSize: d.MaxPackSize,
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
}

func (s *Server) Handler() http.Handler {
	return logRequests(s.logger, s.mux)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleListPacks(w http.ResponseWriter, r *http.Request) {
	lang := r.URL.Query().Get("language")
	packs, err := s.db.ListPacks(r.Context(), lang, 50)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "list failed", err)
		return
	}
	if packs == nil {
		packs = []db.Pack{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"packs": packs})
}

func (s *Server) handleGetPack(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	p, versions, err := s.db.GetPack(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "get failed", err)
		return
	}
	if p == nil {
		writeError(w, http.StatusNotFound, "pack not found", nil)
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
		writeError(w, http.StatusInternalServerError, "lookup failed", err)
		return
	}
	if v == nil {
		writeError(w, http.StatusNotFound, "version not found", nil)
		return
	}

	url, err := s.storage.PresignGet(r.Context(), v.StorageKey, 10*time.Minute)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "presign failed", err)
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
		writeError(w, http.StatusBadRequest, "parse multipart", err)
		return
	}
	file, header, err := r.FormFile("pack")
	if err != nil {
		writeError(w, http.StatusBadRequest, `missing "pack" file field`, err)
		return
	}
	defer file.Close()

	if header.Size > s.maxPackSize {
		writeError(w, http.StatusRequestEntityTooLarge,
			fmt.Sprintf("pack exceeds %d bytes", s.maxPackSize), nil)
		return
	}

	data, err := io.ReadAll(io.LimitReader(file, s.maxPackSize+1))
	if err != nil {
		writeError(w, http.StatusBadRequest, "read upload", err)
		return
	}
	if int64(len(data)) > s.maxPackSize {
		writeError(w, http.StatusRequestEntityTooLarge, "pack too large", nil)
		return
	}

	s.ingestAndRespond(w, r, data, "upload", "", UserIDFromContext(r.Context()))
}

func (s *Server) handleImportGitHub(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RepoURL string `json:"repoUrl"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json", err)
		return
	}
	if body.RepoURL == "" {
		writeError(w, http.StatusBadRequest, "repoUrl is required", nil)
		return
	}

	owner, repo, err := github.ParseRepoURL(body.RepoURL)
	if err != nil {
		writeError(w, http.StatusBadRequest, "bad repo url", err)
		return
	}

	rel, err := s.github.LatestRelease(r.Context(), owner, repo)
	if err != nil {
		writeError(w, http.StatusBadGateway, "github fetch failed", err)
		return
	}
	asset := github.FindZipAsset(rel, repo)
	if asset == nil {
		writeError(w, http.StatusUnprocessableEntity, "no .zip asset in latest release", nil)
		return
	}

	zipBytes, err := s.github.DownloadAsset(r.Context(), asset, s.maxPackSize)
	if err != nil {
		writeError(w, http.StatusBadGateway, "asset download failed", err)
		return
	}

	s.ingestAndRespond(w, r, zipBytes, "github", asset.BrowserURL, UserIDFromContext(r.Context()))
}

func (s *Server) ingestAndRespond(w http.ResponseWriter, r *http.Request, data []byte, source, sourceURL, userID string) {
	out, err := s.ingester.Ingest(r.Context(), data, source, sourceURL, userID)
	if errors.Is(err, pack.ErrVersionExists) {
		writeJSON(w, http.StatusConflict, map[string]any{
			"error":      "version already exists",
			"validation": out.Validation,
		})
		return
	}
	if errors.Is(err, pack.ErrNotPackOwner) {
		writeJSON(w, http.StatusForbidden, map[string]any{
			"error":      "this pack id belongs to another user",
			"validation": out.Validation,
		})
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "ingest failed", err)
		return
	}
	if !out.Validation.Ok() {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]any{
			"error":      "validation failed",
			"validation": out.Validation,
		})
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"packId":     out.Validation.Manifest.ID,
		"version":    out.Validation.Manifest.Version,
		"storageKey": out.StorageKey,
		"sha256":     out.Validation.SHA256,
		"sizeBytes":  out.Validation.Size,
	})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, status int, msg string, err error) {
	resp := map[string]string{"error": msg}
	if err != nil {
		resp["detail"] = err.Error()
	}
	writeJSON(w, status, resp)
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
