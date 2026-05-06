package main

import (
	"archive/zip"
	"bytes"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/ata/languageapp/backend/internal/pack"
)

// cmdPackValidate runs the registry's validator against a pack folder or
// .zip file. Folders are zipped on the fly so the validator sees exactly
// what would be uploaded.
func cmdPackValidate(args []string) error {
	fs := flag.NewFlagSet("pack validate", flag.ExitOnError)
	jsonOut := fs.Bool("json", false, "emit results as JSON for CI / editor integration")
	fs.Usage = func() {
		fmt.Fprintln(os.Stderr, `paktly pack validate — run the registry's validator without uploading

USAGE:
  paktly pack validate <path>

The path can be either a folder containing manifest.json or a pre-built .zip.

EXIT CODES:
  0   pack is valid
  2   pack failed validation (each error printed on its own line)
  1   tool failure (file not found, validator init error, ...)`)
		fs.PrintDefaults()
	}
	if err := fs.Parse(reorderArgs(args, []string{"json"})); err != nil {
		return err
	}
	if fs.NArg() != 1 {
		return usageError("paktly pack validate: expected exactly one path argument")
	}
	path := fs.Arg(0)

	zipped, err := loadOrZip(path)
	if err != nil {
		return err
	}

	v, err := pack.NewValidator()
	if err != nil {
		return fmt.Errorf("validator init: %w", err)
	}
	res := v.ValidateZip(zipped)

	if *jsonOut {
		return printJSONResult(res)
	}
	return printTextResult(res, path)
}

// loadOrZip reads `path` as either a .zip file (passes through) or a folder
// (zips on the fly). The result is the byte slice the validator wants.
func loadOrZip(path string) ([]byte, error) {
	info, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return os.ReadFile(path)
	}
	return zipFolder(path)
}

func zipFolder(root string) ([]byte, error) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	abs, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	err = filepath.Walk(root, func(p string, info os.FileInfo, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if info.IsDir() {
			return nil
		}
		// Skip hidden files (.DS_Store, .git, ...) — creators don't want
		// these uploaded and the registry would reject many of them anyway.
		if strings.HasPrefix(filepath.Base(p), ".") {
			return nil
		}
		absP, err := filepath.Abs(p)
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(abs, absP)
		if err != nil {
			return err
		}
		// Always use forward slashes inside zip — pack format is platform
		// independent, and Windows-authored packs would otherwise break.
		rel = filepath.ToSlash(rel)
		w, err := zw.Create(rel)
		if err != nil {
			return err
		}
		f, err := os.Open(p)
		if err != nil {
			return err
		}
		defer func() { _ = f.Close() }()
		_, err = io.Copy(w, f)
		return err
	})
	if err != nil {
		return nil, err
	}
	if err := zw.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func printTextResult(res *pack.ValidationResult, path string) error {
	if res.Ok() {
		ai := "none"
		if res.Manifest.AICapabilities != nil {
			ai = formatAI(res.Manifest.AICapabilities)
		}
		fmt.Printf("OK   %s\n", path)
		fmt.Printf("     id=%s  version=%s  schema=%s\n",
			res.Manifest.ID, res.Manifest.Version, res.Manifest.SchemaVersion)
		fmt.Printf("     size=%s  sha256=%s\n", humanBytes(int(res.Size)), res.SHA256[:12]+"…")
		fmt.Printf("     lessons=%d  ai=%s\n", len(res.Manifest.Lessons), ai)
		// Coverage: only show if the pack ships at least some multi-locale
		// data, otherwise the "(none)" lines are noise on legacy packs.
		if len(res.Coverage.SupportedLocales) > 0 || len(res.Coverage.LocaleCoverage) > 0 {
			fmt.Printf("     supportedLocales=%s\n", formatLocales(res.Coverage.SupportedLocales))
			fmt.Printf("     localeCoverage=%s\n", formatCoverage(res.Coverage.LocaleCoverage))
		}
		return nil
	}
	fmt.Fprintln(os.Stderr, "FAIL", path)
	for _, e := range res.Errors {
		loc := e.File
		if e.Pointer != "" {
			loc = loc + "#" + e.Pointer
		}
		fmt.Fprintf(os.Stderr, "  %s\n    %s\n", loc, e.Message)
	}
	return &cliError{msg: fmt.Sprintf("%d validation issue(s)", len(res.Errors)), code: 2}
}

func printJSONResult(res *pack.ValidationResult) error {
	type jsonError struct {
		File    string `json:"file"`
		Pointer string `json:"pointer,omitempty"`
		Message string `json:"message"`
	}
	type jsonPack struct {
		ID            string `json:"id"`
		Version       string `json:"version"`
		SchemaVersion string `json:"schemaVersion"`
		Size          int64  `json:"size"`
		SHA256        string `json:"sha256"`
		LessonCount   int    `json:"lessonCount"`
	}
	type jsonResult struct {
		Ok     bool        `json:"ok"`
		Errors []jsonError `json:"errors,omitempty"`
		Pack   *jsonPack   `json:"pack,omitempty"`
	}
	r := jsonResult{Ok: res.Ok()}
	for _, e := range res.Errors {
		r.Errors = append(r.Errors, jsonError{File: e.File, Pointer: e.Pointer, Message: e.Message})
	}
	if res.Ok() {
		r.Pack = &jsonPack{
			ID: res.Manifest.ID, Version: res.Manifest.Version, SchemaVersion: res.Manifest.SchemaVersion,
			Size: res.Size, SHA256: res.SHA256, LessonCount: len(res.Manifest.Lessons),
		}
	}
	enc := jsonEncoder()
	if err := enc(os.Stdout, r); err != nil {
		return err
	}
	if !res.Ok() {
		return &cliError{msg: "", code: 2}
	}
	return nil
}

func formatLocales(ls []string) string {
	if len(ls) == 0 {
		return "(none — pack lacks multi-locale translations or core <90% threshold)"
	}
	return strings.Join(ls, ",")
}

func formatCoverage(m map[string]float64) string {
	if len(m) == 0 {
		return "(empty)"
	}
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	// stable display order: descending coverage, alphabetical tie-break
	sortByCoverageDesc(keys, m)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf("%s=%.1f%%", k, m[k]*100))
	}
	return strings.Join(parts, " ")
}

func sortByCoverageDesc(keys []string, m map[string]float64) {
	for i := 1; i < len(keys); i++ {
		for j := i; j > 0; j-- {
			a, b := keys[j-1], keys[j]
			if m[a] < m[b] || (m[a] == m[b] && a > b) {
				keys[j-1], keys[j] = b, a
				continue
			}
			break
		}
	}
}

func formatAI(c *pack.AICapabilities) string {
	flags := []string{}
	if c.QuestionGeneration {
		flags = append(flags, "questionGeneration")
	}
	if c.Explanation {
		flags = append(flags, "explanation")
	}
	if c.Conversation {
		flags = append(flags, "conversation")
	}
	if c.Hint {
		flags = append(flags, "hint")
	}
	if len(flags) == 0 {
		return "(none enabled)"
	}
	return strings.Join(flags, ",")
}

func humanBytes(n int) string {
	const k = 1024
	switch {
	case n < k:
		return fmt.Sprintf("%dB", n)
	case n < k*k:
		return fmt.Sprintf("%.1fKB", float64(n)/k)
	case n < k*k*k:
		return fmt.Sprintf("%.1fMB", float64(n)/(k*k))
	default:
		return fmt.Sprintf("%.1fGB", float64(n)/(k*k*k))
	}
}
