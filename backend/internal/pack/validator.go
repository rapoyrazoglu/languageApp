package pack

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"path"
	"strings"

	"github.com/santhosh-tekuri/jsonschema/v6"
	"golang.org/x/text/language"
	"golang.org/x/text/message"
)

// msgPrinter is required by jsonschema/v6 — some Kind types (Pattern, Format, …)
// format their human-readable message with golang.org/x/text/message and panic
// on a nil printer. Using English everywhere is fine; messages are developer-
// facing, not end-user.
var msgPrinter = message.NewPrinter(language.English)

//go:embed schemas/*.json
var schemaFS embed.FS

// ValidationResult is what the API returns to the user.
type ValidationResult struct {
	Manifest *Manifest       `json:"manifest,omitempty"`
	SHA256   string          `json:"sha256"`
	Size     int64           `json:"size"`
	Errors   []ValidationErr `json:"errors,omitempty"`
}

type ValidationErr struct {
	File    string `json:"file,omitempty"`
	Pointer string `json:"pointer,omitempty"`
	Message string `json:"message"`
}

func (r *ValidationResult) Ok() bool { return len(r.Errors) == 0 }

// Validator holds compiled JSON schemas and is safe for concurrent use.
type Validator struct {
	manifestSchema *jsonschema.Schema
	lessonSchema   *jsonschema.Schema
}

func NewValidator() (*Validator, error) {
	c := jsonschema.NewCompiler()

	if err := addSchema(c, "schemas/manifest.schema.json"); err != nil {
		return nil, err
	}
	if err := addSchema(c, "schemas/lesson.schema.json"); err != nil {
		return nil, err
	}

	manifestSchema, err := c.Compile("schemas/manifest.schema.json")
	if err != nil {
		return nil, fmt.Errorf("compile manifest schema: %w", err)
	}
	lessonSchema, err := c.Compile("schemas/lesson.schema.json")
	if err != nil {
		return nil, fmt.Errorf("compile lesson schema: %w", err)
	}

	return &Validator{manifestSchema: manifestSchema, lessonSchema: lessonSchema}, nil
}

func addSchema(c *jsonschema.Compiler, path string) error {
	data, err := schemaFS.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read embedded %s: %w", path, err)
	}
	var doc any
	if err := json.Unmarshal(data, &doc); err != nil {
		return fmt.Errorf("parse %s: %w", path, err)
	}
	return c.AddResource(path, doc)
}

// ValidateZip runs the full pack pipeline on a zip file's bytes.
func (v *Validator) ValidateZip(data []byte) *ValidationResult {
	res := &ValidationResult{
		SHA256: sha256Hex(data),
		Size:   int64(len(data)),
	}

	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		res.Errors = append(res.Errors, ValidationErr{Message: "invalid zip: " + err.Error()})
		return res
	}

	files, root, err := indexZipFiles(zr)
	if err != nil {
		res.Errors = append(res.Errors, ValidationErr{Message: err.Error()})
		return res
	}

	manifestPath := path.Join(root, "manifest.json")
	manifestFile, ok := files[manifestPath]
	if !ok {
		res.Errors = append(res.Errors, ValidationErr{Message: "manifest.json not found at pack root"})
		return res
	}

	manifestBytes, err := readZipEntry(manifestFile)
	if err != nil {
		res.Errors = append(res.Errors, ValidationErr{File: "manifest.json", Message: err.Error()})
		return res
	}

	var manifestDoc any
	if err := json.Unmarshal(manifestBytes, &manifestDoc); err != nil {
		res.Errors = append(res.Errors, ValidationErr{File: "manifest.json", Message: "not valid JSON: " + err.Error()})
		return res
	}
	if err := v.manifestSchema.Validate(manifestDoc); err != nil {
		appendSchemaErrors(res, "manifest.json", err)
		return res
	}

	var manifest Manifest
	if err := json.Unmarshal(manifestBytes, &manifest); err != nil {
		res.Errors = append(res.Errors, ValidationErr{File: "manifest.json", Message: "decode: " + err.Error()})
		return res
	}
	res.Manifest = &manifest

	// Each lesson file must exist and validate.
	for _, lref := range manifest.Lessons {
		lessonPath := path.Join(root, lref.File)
		lf, ok := files[lessonPath]
		if !ok {
			res.Errors = append(res.Errors, ValidationErr{File: lref.File, Message: "referenced by manifest but missing in zip"})
			continue
		}
		lb, err := readZipEntry(lf)
		if err != nil {
			res.Errors = append(res.Errors, ValidationErr{File: lref.File, Message: err.Error()})
			continue
		}
		var lDoc any
		if err := json.Unmarshal(lb, &lDoc); err != nil {
			res.Errors = append(res.Errors, ValidationErr{File: lref.File, Message: "not valid JSON: " + err.Error()})
			continue
		}
		if err := v.lessonSchema.Validate(lDoc); err != nil {
			appendSchemaErrors(res, lref.File, err)
			continue
		}

		// Verify lesson id matches manifest reference.
		var lesson struct {
			ID     string `json:"id"`
			Blocks []struct {
				Type         string `json:"type"`
				ExerciseType string `json:"exerciseType,omitempty"`
				Items        []struct {
					Audio    string `json:"audio,omitempty"`
					Image    string `json:"image,omitempty"`
					Examples []struct {
						Audio string `json:"audio,omitempty"`
					} `json:"examples,omitempty"`
				} `json:"items,omitempty"`
				Media *struct {
					Audio string `json:"audio,omitempty"`
					Image string `json:"image,omitempty"`
					Video string `json:"video,omitempty"`
				} `json:"media,omitempty"`
			} `json:"blocks"`
		}
		_ = json.Unmarshal(lb, &lesson)
		if lesson.ID != lref.ID {
			res.Errors = append(res.Errors, ValidationErr{
				File:    lref.File,
				Message: fmt.Sprintf("lesson id %q does not match manifest id %q", lesson.ID, lref.ID),
			})
		}

		// Check media references.
		for _, b := range lesson.Blocks {
			for _, it := range b.Items {
				checkMedia(res, files, root, lref.File, it.Audio)
				checkMedia(res, files, root, lref.File, it.Image)
				for _, ex := range it.Examples {
					checkMedia(res, files, root, lref.File, ex.Audio)
				}
			}
			if b.Media != nil {
				checkMedia(res, files, root, lref.File, b.Media.Audio)
				checkMedia(res, files, root, lref.File, b.Media.Image)
				checkMedia(res, files, root, lref.File, b.Media.Video)
			}
		}
	}

	return res
}

func checkMedia(res *ValidationResult, files map[string]*zip.File, root, lessonFile, ref string) {
	if ref == "" {
		return
	}
	full := path.Join(root, ref)
	if _, ok := files[full]; !ok {
		res.Errors = append(res.Errors, ValidationErr{
			File:    lessonFile,
			Message: fmt.Sprintf("missing media file: %s", ref),
		})
	}
}

// indexZipFiles returns a map keyed by normalized path and the detected root prefix.
// If every entry shares the same top-level directory, that directory is treated as root.
func indexZipFiles(zr *zip.Reader) (map[string]*zip.File, string, error) {
	files := make(map[string]*zip.File, len(zr.File))
	var roots = make(map[string]struct{})

	for _, f := range zr.File {
		// Defend against zip-slip and absolute paths.
		clean := path.Clean(f.Name)
		if strings.HasPrefix(clean, "..") || strings.HasPrefix(clean, "/") {
			return nil, "", fmt.Errorf("unsafe path in zip: %s", f.Name)
		}
		if f.FileInfo().IsDir() {
			continue
		}
		files[clean] = f
		// Track top-level directory.
		if i := strings.IndexByte(clean, '/'); i > 0 {
			roots[clean[:i]] = struct{}{}
		} else {
			roots[""] = struct{}{}
		}
	}

	if len(roots) == 1 {
		for r := range roots {
			return files, r, nil
		}
	}
	return files, "", nil
}

func readZipEntry(f *zip.File) ([]byte, error) {
	rc, err := f.Open()
	if err != nil {
		return nil, err
	}
	defer func() { _ = rc.Close() }()
	const maxLessonBytes = 5 * 1024 * 1024 // 5 MB safety limit per file
	return io.ReadAll(io.LimitReader(rc, maxLessonBytes))
}

func appendSchemaErrors(res *ValidationResult, file string, err error) {
	if verr, ok := err.(*jsonschema.ValidationError); ok {
		for _, leaf := range verr.BasicOutput().Errors {
			if leaf.Error.Kind == nil {
				continue
			}
			res.Errors = append(res.Errors, ValidationErr{
				File:    file,
				Pointer: leaf.InstanceLocation,
				Message: leaf.Error.Kind.LocalizedString(msgPrinter),
			})
		}
		if len(res.Errors) == 0 {
			res.Errors = append(res.Errors, ValidationErr{File: file, Message: err.Error()})
		}
		return
	}
	res.Errors = append(res.Errors, ValidationErr{File: file, Message: err.Error()})
}

func sha256Hex(b []byte) string {
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}
