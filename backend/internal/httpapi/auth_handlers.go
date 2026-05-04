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
		writeAPIError(w, http.StatusBadRequest, CodeInvalidJSON, "invalid JSON body")
		return
	}
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if _, err := mail.ParseAddress(req.Email); err != nil {
		writeAPIError(w, http.StatusBadRequest, CodeBadRequest, "invalid email",
			FieldError{Path: "email", Message: "must be a valid address"})
		return
	}

	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, CodeBadRequest, err.Error(),
			FieldError{Path: "password", Message: err.Error()})
		return
	}

	user, err := s.db.CreateUser(r.Context(), req.Email, hash, strings.TrimSpace(req.DisplayName))
	if errors.Is(err, db.ErrEmailTaken) {
		writeAPIError(w, http.StatusConflict, CodeEmailTaken, "email already registered")
		return
	}
	if err != nil {
		s.logger.Error("create user", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "could not create user")
		return
	}

	s.issueTokenResponse(w, user, http.StatusCreated)
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeAPIError(w, http.StatusBadRequest, CodeInvalidJSON, "invalid JSON body")
		return
	}
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))

	user, err := s.db.GetUserByEmail(r.Context(), req.Email)
	if err != nil {
		s.logger.Error("get user", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "lookup failed")
		return
	}
	if user == nil {
		// Don't leak whether the email exists.
		writeAPIError(w, http.StatusUnauthorized, CodeUnauthorized, "invalid email or password")
		return
	}
	if err := auth.CheckPassword(user.PasswordHash, req.Password); err != nil {
		writeAPIError(w, http.StatusUnauthorized, CodeUnauthorized, "invalid email or password")
		return
	}

	s.issueTokenResponse(w, user, http.StatusOK)
}

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	uid := UserIDFromContext(r.Context())
	user, err := s.db.GetUserByID(r.Context(), uid)
	if err != nil {
		s.logger.Error("get user", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "lookup failed")
		return
	}
	if user == nil {
		writeAPIError(w, http.StatusNotFound, CodeNotFound, "user not found")
		return
	}
	writeJSON(w, http.StatusOK, user)
}

func (s *Server) issueTokenResponse(w http.ResponseWriter, user *db.User, status int) {
	token, exp, err := s.tokens.Issue(user.ID, user.Email)
	if err != nil {
		s.logger.Error("issue token", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "could not issue token")
		return
	}
	writeJSON(w, status, tokenResp{
		Token:     token,
		ExpiresAt: exp.Format("2006-01-02T15:04:05Z07:00"),
		User:      user,
	})
}
