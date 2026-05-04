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
			writeAPIError(w, http.StatusUnauthorized, CodeUnauthorized, "missing bearer token")
			return
		}
		claims, err := s.tokens.Verify(token)
		if err != nil {
			if errors.Is(err, auth.ErrTokenExpired) {
				writeAPIError(w, http.StatusUnauthorized, CodeTokenExpired, "token expired")
				return
			}
			writeAPIError(w, http.StatusUnauthorized, CodeUnauthorized, "invalid token")
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
