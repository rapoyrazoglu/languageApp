package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/ata/languageapp/backend/internal/auth"
)

type ctxKey int

const userIDKey ctxKey = iota

// requireAuth wraps a handler so it only runs with a valid JWT.
// On success the user id is available via UserIDFromContext.
func (s *Server) requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := bearerToken(r)
		if token == "" {
			writeError(w, http.StatusUnauthorized, "missing bearer token", nil)
			return
		}
		claims, err := s.tokens.Verify(token)
		if err != nil {
			status := http.StatusUnauthorized
			msg := "invalid token"
			if errors.Is(err, auth.ErrTokenExpired) {
				msg = "token expired"
			}
			writeError(w, status, msg, nil)
			return
		}
		ctx := context.WithValue(r.Context(), userIDKey, claims.UserID)
		next(w, r.WithContext(ctx))
	}
}

func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if len(h) > len(prefix) && strings.EqualFold(h[:len(prefix)], prefix) {
		return strings.TrimSpace(h[len(prefix):])
	}
	return ""
}

// UserIDFromContext returns the authenticated user id, or "" if absent.
func UserIDFromContext(ctx context.Context) string {
	v, _ := ctx.Value(userIDKey).(string)
	return v
}
