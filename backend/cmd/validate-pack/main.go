// Command validate-pack runs a pack zip through the registry's validator
// without uploading anything. Useful for authors who want to confirm a pack
// passes schema + media-reference checks before publishing.
//
//	go run ./cmd/validate-pack mypack.zip
//
// On success, prints a one-line summary; on failure, prints each
// validation error and exits non-zero.
package main

import (
	"fmt"
	"os"

	"github.com/ata/languageapp/backend/internal/pack"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: validate-pack <pack.zip>")
		os.Exit(2)
	}
	v, err := pack.NewValidator()
	if err != nil {
		fmt.Fprintln(os.Stderr, "validator init:", err)
		os.Exit(1)
	}
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, "read zip:", err)
		os.Exit(1)
	}
	res := v.ValidateZip(data)
	if res.Ok() {
		ai := "none"
		if res.Manifest.AICapabilities != nil {
			ai = fmt.Sprintf("%+v", *res.Manifest.AICapabilities)
		}
		fmt.Printf("OK  schema=%s  id=%s  version=%s  size=%d  sha256=%s  ai=%s\n",
			res.Manifest.SchemaVersion, res.Manifest.ID, res.Manifest.Version,
			res.Size, res.SHA256, ai)
		return
	}
	fmt.Fprintln(os.Stderr, "FAIL")
	for _, e := range res.Errors {
		loc := e.File
		if e.Pointer != "" {
			loc = loc + "#" + e.Pointer
		}
		fmt.Fprintf(os.Stderr, "  %s: %s\n", loc, e.Message)
	}
	os.Exit(2)
}
