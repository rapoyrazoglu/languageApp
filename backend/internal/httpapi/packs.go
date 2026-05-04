package httpapi

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/ata/languageapp/backend/internal/db"
)

// handleListPacks supports filter + cursor pagination.
//
// Query params:
//
//	language=ja        ISO 639 code, exact match
//	level=A1           level filter, exact match
//	tag=hiragana       tag filter (any-of in the tags array)
//	q=hello            free-text search over name + description
//	limit=50           1..100, default 50
//	cursor=...         opaque, from a previous response
func (s *Server) handleListPacks(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()

	limit := 0
	if raw := q.Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > 100 {
			writeAPIError(w, http.StatusBadRequest, CodeBadRequest,
				"invalid limit",
				FieldError{Path: "query.limit", Message: "must be an integer in [1, 100]"})
			return
		}
		limit = n
	}

	res, err := s.db.SearchPacks(r.Context(), db.SearchOpts{
		Language: q.Get("language"),
		Level:    q.Get("level"),
		Tag:      q.Get("tag"),
		Query:    q.Get("q"),
		Limit:    limit,
		Cursor:   q.Get("cursor"),
	})
	if err != nil {
		// Cursor decoding errors come back here; treat as 400 if it looks like one.
		if strings.HasPrefix(err.Error(), "bad cursor:") {
			writeAPIError(w, http.StatusBadRequest, CodeBadRequest, "invalid cursor",
				FieldError{Path: "query.cursor", Message: "could not decode"})
			return
		}
		s.logger.Error("search packs", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "search failed")
		return
	}
	writeJSON(w, http.StatusOK, res)
}
