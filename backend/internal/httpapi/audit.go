package httpapi

import (
	"net/http"

	"github.com/ata/languageapp/backend/internal/db"
)

// handleListAudit returns the audit trail for a pack id.
// Auth required: only the pack owner can read it.
func (s *Server) handleListAudit(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	uid := UserIDFromContext(r.Context())

	owner, err := s.db.PackOwner(r.Context(), id)
	if err != nil {
		s.logger.Error("pack owner lookup", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "lookup failed")
		return
	}
	if owner == "" {
		writeAPIError(w, http.StatusNotFound, CodeNotFound, "pack not found")
		return
	}
	if owner != uid {
		writeAPIError(w, http.StatusForbidden, CodeForbidden, "only the pack owner can view audit log")
		return
	}

	entries, err := s.db.ListAudit(r.Context(), id, 100)
	if err != nil {
		s.logger.Error("list audit", "err", err)
		writeAPIError(w, http.StatusInternalServerError, CodeInternal, "audit query failed")
		return
	}
	if entries == nil {
		entries = []db.AuditEntry{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": entries})
}
