package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/ata/languageapp/backend/internal/pack"
)

// cmdPackPublish zips the pack (if a folder), validates it locally, then
// POSTs it as multipart/form-data to <registry>/v1/packs/upload. We always
// validate before sending so the user sees errors locally instead of
// learning about them from a 422 round-trip.
func cmdPackPublish(args []string) error {
	fs := flag.NewFlagSet("pack publish", flag.ExitOnError)
	registryFlag := fs.String("registry", "", "registry base URL (overrides env / config)")
	tokenFlag := fs.String("token", "", "auth token (overrides env / config)")
	skipValidate := fs.Bool("skip-validate", false, "DON'T run local validation first (not recommended)")
	fs.Usage = func() {
		fmt.Fprintln(os.Stderr, `paktly pack publish — upload a pack to the registry

USAGE:
  paktly pack publish <path> [flags]

The path can be a folder (zipped on the fly) or a pre-built .zip.

CONFIGURATION:
  --registry takes precedence over PAKTLY_REGISTRY which takes precedence
  over the saved config (~/.config/paktly/config.json). Same for --token /
  PAKTLY_TOKEN. Default registry is https://api.paktly.dev.`)
		fs.PrintDefaults()
	}
	if err := fs.Parse(reorderArgs(args, []string{"skip-validate"})); err != nil {
		return err
	}
	if fs.NArg() != 1 {
		return usageError("paktly pack publish: expected exactly one path argument")
	}
	path := fs.Arg(0)

	cfg := resolveConfig()
	if *registryFlag != "" {
		cfg.Registry = *registryFlag
	}
	if *tokenFlag != "" {
		cfg.Token = *tokenFlag
	}

	zipped, err := loadOrZip(path)
	if err != nil {
		return err
	}

	if !*skipValidate {
		v, err := pack.NewValidator()
		if err != nil {
			return fmt.Errorf("validator init: %w", err)
		}
		res := v.ValidateZip(zipped)
		if !res.Ok() {
			fmt.Fprintln(os.Stderr, "FAIL", path)
			for _, e := range res.Errors {
				loc := e.File
				if e.Pointer != "" {
					loc = loc + "#" + e.Pointer
				}
				fmt.Fprintf(os.Stderr, "  %s\n    %s\n", loc, e.Message)
			}
			return &cliError{msg: fmt.Sprintf("local validation failed (%d issue(s)) — fix or pass --skip-validate", len(res.Errors)), code: 2}
		}
	}

	token, err := requireToken(cfg)
	if err != nil {
		return err
	}

	result, err := uploadToRegistry(cfg.Registry, token, path, zipped)
	if err != nil {
		return err
	}
	fmt.Printf("PUBLISHED  %s@%s\n", result.PackID, result.Version)
	fmt.Printf("           sha256=%s  size=%s\n", result.SHA256[:12]+"…", humanBytes(int(result.SizeBytes)))
	fmt.Printf("           registry=%s\n", cfg.Registry)
	return nil
}

// IngestResult mirrors the registry's response. We only quote what the user
// needs in console output; future fields decode silently.
type IngestResult struct {
	PackID    string `json:"packId"`
	Version   string `json:"version"`
	SHA256    string `json:"sha256"`
	SizeBytes int64  `json:"sizeBytes"`
}

// APIError mirrors the structured error envelope from the registry. Codes
// are stable so callers (here: pretty-printer) can switch on them.
type APIError struct {
	Code    string          `json:"code"`
	Message string          `json:"message"`
	Fields  []APIErrorField `json:"fields,omitempty"`
}

type APIErrorField struct {
	Path    string `json:"path"`
	Message string `json:"message"`
}

type APIErrorBody struct {
	Error APIError `json:"error"`
}

func uploadToRegistry(registry, token, originalPath string, zipped []byte) (*IngestResult, error) {
	url := strings.TrimRight(registry, "/") + "/v1/packs/upload"

	body := &bytes.Buffer{}
	w := multipart.NewWriter(body)
	filename := filepath.Base(originalPath)
	if !strings.HasSuffix(filename, ".zip") {
		filename = filename + ".zip"
	}
	part, err := w.CreateFormFile("pack", filename)
	if err != nil {
		return nil, fmt.Errorf("multipart: %w", err)
	}
	if _, err := io.Copy(part, bytes.NewReader(zipped)); err != nil {
		return nil, fmt.Errorf("multipart copy: %w", err)
	}
	if err := w.Close(); err != nil {
		return nil, fmt.Errorf("multipart close: %w", err)
	}

	req, err := http.NewRequest("POST", url, body)
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept", "application/json")

	client := &http.Client{Timeout: 5 * time.Minute}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("upload: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		var r IngestResult
		if err := json.Unmarshal(respBody, &r); err != nil {
			return nil, fmt.Errorf("decode response: %w (body: %s)", err, truncate(respBody, 200))
		}
		return &r, nil
	}

	var envelope APIErrorBody
	if err := json.Unmarshal(respBody, &envelope); err == nil && envelope.Error.Code != "" {
		var sb strings.Builder
		fmt.Fprintf(&sb, "registry rejected upload (%d %s): %s", resp.StatusCode, envelope.Error.Code, envelope.Error.Message)
		for _, f := range envelope.Error.Fields {
			fmt.Fprintf(&sb, "\n  %s: %s", f.Path, f.Message)
		}
		return nil, &cliError{msg: sb.String(), code: 1}
	}
	return nil, &cliError{
		msg:  fmt.Sprintf("registry returned HTTP %d (body: %s)", resp.StatusCode, truncate(respBody, 400)),
		code: 1,
	}
}

func truncate(b []byte, n int) string {
	if len(b) <= n {
		return string(b)
	}
	return string(b[:n]) + "…"
}

// jsonEncoder returns a closure that writes pretty JSON to a writer. Pulled
// out so the validate command can share it cleanly.
func jsonEncoder() func(io.Writer, any) error {
	return func(w io.Writer, v any) error {
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		return enc.Encode(v)
	}
}
