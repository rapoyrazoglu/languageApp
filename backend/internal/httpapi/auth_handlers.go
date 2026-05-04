package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/mail"
	"strings"

	"github.com/ata/languageapp/backend/internal/auth"
	"github.com/ata/languageapp/backend/internal/db"
)

type registerReq struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	DisplayName string `json:"displayName,omitempty"`
}

type loginReq struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type tokenResp struct {
	Token     string   `json:"token"`
	ExpiresAt string   `json:"expiresAt"`
	User      *db.User `json:"user"`
}

func (s *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	var req registerReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json", err)
		return
	}
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if _, err := mail.ParseAddress(req.Email); err != nil {
		writeError(w, http.StatusBadRequest, "invalid email", nil)
		return
	}

	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error(), nil)
		return
	}

	user, err := s.db.CreateUser(r.Context(), req.Email, hash, strings.TrimSpace(req.DisplayName))
	if errors.Is(err, db.ErrEmailTaken) {
		writeError(w, http.StatusConflict, "email already registered", nil)
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "create user", err)
		return
	}

	s.issueTokenResponse(w, user, http.StatusCreated)
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json", err)
		return
	}
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))

	user, err := s.db.GetUserByEmail(r.Context(), req.Email)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "lookup", err)
		return
	}
	if user == nil {
		// Don't leak whether the email exists.
		writeError(w, http.StatusUnauthorized, "invalid email or password", nil)
		return
	}
	if err := auth.CheckPassword(user.PasswordHash, req.Password); err != nil {
		writeError(w, http.StatusUnauthorized, "invalid email or password", nil)
		return
	}

	s.issueTokenResponse(w, user, http.StatusOK)
}

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	uid := UserIDFromContext(r.Context())
	user, err := s.db.GetUserByID(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "lookup", err)
		return
	}
	if user == nil {
		writeError(w, http.StatusNotFound, "user not found", nil)
		return
	}
	writeJSON(w, http.StatusOK, user)
}

func (s *Server) issueTokenResponse(w http.ResponseWriter, user *db.User, status int) {
	token, exp, err := s.tokens.Issue(user.ID, user.Email)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "issue token", err)
		return
	}
	writeJSON(w, status, tokenResp{
		Token:     token,
		ExpiresAt: exp.Format("2006-01-02T15:04:05Z07:00"),
		User:      user,
	})
}
