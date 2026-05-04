package httpapi

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/ata/languageapp/backend/internal/pack"
)

// Error codes returned in the `error.code` field. Stable string identifiers —
// SDKs may switch on these. Do not rename without bumping the API contract.
const (
	CodeBadRequest          = "BAD_REQUEST"
	CodeInvalidJSON         = "INVALID_JSON"
	CodeMissingField        = "MISSING_FIELD"
	CodeUnauthorized        = "UNAUTHORIZED"
	CodeTokenExpired        = "TOKEN_EXPIRED"
	CodeForbidden           = "FORBIDDEN"
	CodeNotFound            = "NOT_FOUND"
	CodeConflict            = "CONFLICT"
	CodeEmailTaken          = "EMAIL_TAKEN"
	CodeVersionExists       = "VERSION_EXISTS"
	CodePackOwnerMismatch   = "PACK_OWNER_MISMATCH"
	CodeValidationFailed    = "PACK_VALIDATION_FAILED"
	CodePayloadTooLarge     = "PAYLOAD_TOO_LARGE"
	CodeRateLimited         = "RATE_LIMITED"
	CodeBadGateway          = "BAD_GATEWAY"
	CodeInternal            = "INTERNAL"
)

// APIError is the body shape for every non-2xx response.
type APIError struct {
	Code    string       `json:"code"`
	Message string       `json:"message"`
	Fields  []FieldError `json:"fields,omitempty"`
}

// FieldError points at a specific input that failed validation. `Path` follows
// JSON Pointer semantics for body errors, or `query.<name>` for query params,
// or `<file>#<pointer>` for pack file errors.
type FieldError struct {
	Path    string `json:"path"`
	Message string `json:"message"`
}

type errorResponse struct {
	Error APIError `json:"error"`
}

func writeAPIError(w http.ResponseWriter, status int, code, message string, fields ...FieldError) {
	writeJSON(w, status, errorResponse{Error: APIError{
		Code:    code,
		Message: message,
		Fields:  fields,
	}})
}

// writePackValidationError turns a pack.ValidationResult into the standard error shape.
// Used by the ingest endpoints when the zip itself is the problem.
func writePackValidationError(w http.ResponseWriter, status int, code, message string, vr *pack.ValidationResult) {
	var fields []FieldError
	if vr != nil {
		for _, e := range vr.Errors {
			fields = append(fields, FieldError{
				Path:    formatPackPath(e.File, e.Pointer),
				Message: e.Message,
			})
		}
	}
	writeAPIError(w, status, code, message, fields...)
}

func formatPackPath(file, pointer string) string {
	switch {
	case file == "" && pointer == "":
		return ""
	case file == "":
		return pointer
	case pointer == "":
		return file
	default:
		return fmt.Sprintf("%s#%s", file, pointer)
	}
}

// writeJSON is the single place that emits a body. Status defaults to 200.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
