package main

import (
	"bufio"
	"embed"
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"text/template"
)

//go:embed templates/*
var templatesFS embed.FS

// cmdPackNew scaffolds a new pack folder ready for the creator to edit and
// publish. Tries hard to be friendly: missing flags prompt interactively,
// the destination folder is rejected if it already exists, and the resulting
// pack passes `paktly pack validate .` out of the box.
func cmdPackNew(args []string) error {
	fs := flag.NewFlagSet("pack new", flag.ExitOnError)
	idFlag := fs.String("id", "", "reverse-DNS id, e.g. com.github.ata.my-pack")
	nameFlag := fs.String("name", "", "human-readable pack name")
	descFlag := fs.String("description", "", "one-line pack description")
	langCodeFlag := fs.String("language", "", "ISO 639 code of the language being learned, e.g. ja")
	uiLangFlag := fs.String("ui-language", "", "ISO 639 code of the explanation language, e.g. en")
	levelFlag := fs.String("level", "", "CEFR level: A1, A2, B1, B2, C1, C2, or 'mixed'")
	authorFlag := fs.String("author", "", "your name (the pack author)")
	dirFlag := fs.String("dir", "", "destination directory (default: ./<slug>)")
	fs.Usage = func() {
		fmt.Fprintln(os.Stderr, `paktly pack new — scaffold a new pack folder

USAGE:
  paktly pack new <slug> [flags]

ARGUMENTS:
  <slug>    folder name (and the last segment of the pack id when --id is omitted).
            Must match [a-z0-9][a-z0-9-]+.

FLAGS:`)
		fs.PrintDefaults()
		fmt.Fprintln(os.Stderr, `
EXAMPLE:
  paktly pack new nihongo-n5 --language ja --ui-language tr --level A1 --author "Ata"`)
	}
	if err := fs.Parse(reorderArgs(args, nil)); err != nil {
		return err
	}
	if fs.NArg() != 1 {
		return usageError("paktly pack new: expected exactly one slug argument")
	}
	slug := fs.Arg(0)
	if !slugPattern.MatchString(slug) {
		return usageError("invalid slug %q: must match %s", slug, slugPattern.String())
	}

	in := bufio.NewReader(os.Stdin)
	answers := scaffoldAnswers{
		Slug:         slug,
		ID:           *idFlag,
		Name:         *nameFlag,
		Description:  *descFlag,
		LanguageCode: *langCodeFlag,
		UILanguage:   *uiLangFlag,
		Level:        *levelFlag,
		AuthorName:   *authorFlag,
	}
	if err := answers.fillFromPrompts(in, os.Stdout); err != nil {
		return err
	}
	answers.applyDefaults()

	dest := *dirFlag
	if dest == "" {
		dest = slug
	}
	if _, err := os.Stat(dest); err == nil {
		return fmt.Errorf("destination %q already exists; pick a fresh folder", dest)
	}

	if err := writeScaffold(dest, answers); err != nil {
		return fmt.Errorf("scaffold: %w", err)
	}

	fmt.Printf("created %s/\n", dest)
	fmt.Println("next steps:")
	fmt.Printf("  cd %s\n", dest)
	fmt.Println("  # edit lessons/001-getting-started.json")
	fmt.Println("  paktly pack validate .")
	fmt.Println("  paktly pack publish .")
	return nil
}

var slugPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]+$`)

// scaffoldAnswers carries everything the templates need. Exported field
// names so text/template can address them.
type scaffoldAnswers struct {
	Slug               string
	ID                 string
	Name               string
	Description        string
	LanguageCode       string
	LanguageName       string
	LanguageNativeName string
	UILanguage         string
	Level              string
	AuthorName         string
	SampleTarget       string
}

func (a *scaffoldAnswers) fillFromPrompts(in *bufio.Reader, out *os.File) error {
	prompts := []struct {
		field    *string
		question string
		fallback func() string
	}{
		{&a.ID, "Pack id (reverse-DNS)", func() string { return defaultID(a.AuthorName, a.Slug) }},
		{&a.Name, "Pack name", func() string { return titleCase(a.Slug) }},
		{&a.Description, "One-line description", func() string { return "" }},
		{&a.LanguageCode, "Target language code (e.g. ja)", func() string { return "" }},
		{&a.UILanguage, "UI language (e.g. en, tr)", func() string { return "en" }},
		{&a.Level, "CEFR level (A1/A2/B1/B2/C1/C2/mixed)", func() string { return "A1" }},
		{&a.AuthorName, "Author name", func() string { return "" }},
	}
	for _, p := range prompts {
		if *p.field != "" {
			continue
		}
		def := p.fallback()
		if def != "" {
			_, _ = fmt.Fprintf(out, "%s [%s]: ", p.question, def)
		} else {
			_, _ = fmt.Fprintf(out, "%s: ", p.question)
		}
		line, err := in.ReadString('\n')
		if err != nil && line == "" {
			return fmt.Errorf("reading %s: %w", p.question, err)
		}
		line = strings.TrimSpace(line)
		if line == "" {
			line = def
		}
		*p.field = line
	}
	return nil
}

func (a *scaffoldAnswers) applyDefaults() {
	if a.ID == "" {
		a.ID = defaultID(a.AuthorName, a.Slug)
	}
	if a.Name == "" {
		a.Name = titleCase(a.Slug)
	}
	if a.Level == "" {
		a.Level = "A1"
	}
	if a.UILanguage == "" {
		a.UILanguage = "en"
	}
	a.LanguageName = languageDisplayName(a.LanguageCode)
	a.LanguageNativeName = languageNativeName(a.LanguageCode)
	a.SampleTarget = sampleWord(a.LanguageCode)
}

func writeScaffold(dest string, answers scaffoldAnswers) error {
	if err := os.MkdirAll(filepath.Join(dest, "lessons"), 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Join(dest, "media", "audio"), 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Join(dest, "media", "images"), 0o755); err != nil {
		return err
	}

	files := map[string]string{
		"templates/manifest.json.tmpl":   filepath.Join(dest, "manifest.json"),
		"templates/README.md.tmpl":       filepath.Join(dest, "README.md"),
		"templates/LICENSE.tmpl":         filepath.Join(dest, "LICENSE"),
		"templates/lesson_001.json.tmpl": filepath.Join(dest, "lessons", "001-getting-started.json"),
	}
	for tmplPath, outPath := range files {
		if err := renderTemplate(tmplPath, outPath, answers); err != nil {
			return fmt.Errorf("render %s: %w", tmplPath, err)
		}
	}
	return nil
}

func renderTemplate(tmplPath, outPath string, data any) error {
	src, err := fs.ReadFile(templatesFS, tmplPath)
	if err != nil {
		return err
	}
	tmpl, err := template.New(filepath.Base(tmplPath)).Parse(string(src))
	if err != nil {
		return err
	}
	out, err := os.Create(outPath)
	if err != nil {
		return err
	}
	defer func() { _ = out.Close() }()
	return tmpl.Execute(out, data)
}

// MARK: - Helpers

func defaultID(author, slug string) string {
	a := strings.ToLower(strings.ReplaceAll(strings.TrimSpace(author), " ", "-"))
	if a == "" {
		a = "creator"
	}
	return fmt.Sprintf("com.github.%s.%s", a, slug)
}

func titleCase(slug string) string {
	parts := strings.Split(slug, "-")
	for i, p := range parts {
		if p == "" {
			continue
		}
		parts[i] = strings.ToUpper(p[:1]) + p[1:]
	}
	return strings.Join(parts, " ")
}

// languageDisplayName maps the most common ISO 639 codes to human-readable
// names. Unknown codes fall through to the code itself — creators can edit
// the manifest after scaffolding.
func languageDisplayName(code string) string {
	c := strings.ToLower(code)
	if name, ok := languageNames[c]; ok {
		return name
	}
	return code
}

func languageNativeName(code string) string {
	c := strings.ToLower(code)
	if name, ok := languageNativeNames[c]; ok {
		return name
	}
	return ""
}

func sampleWord(code string) string {
	c := strings.ToLower(code)
	if w, ok := sampleWords[c]; ok {
		return w
	}
	return "hello"
}

var languageNames = map[string]string{
	"en": "English", "tr": "Turkish", "de": "German", "es": "Spanish",
	"fr": "French", "it": "Italian", "pt": "Portuguese", "ru": "Russian",
	"nl": "Dutch", "ja": "Japanese", "ko": "Korean", "zh": "Chinese",
	"zh-hans": "Chinese (Simplified)", "zh-hant": "Chinese (Traditional)",
	"ar": "Arabic", "he": "Hebrew", "hi": "Hindi", "vi": "Vietnamese",
	"th": "Thai", "id": "Indonesian", "pl": "Polish", "sv": "Swedish",
	"el": "Greek", "uk": "Ukrainian", "ro": "Romanian", "cs": "Czech",
	"hu": "Hungarian", "fi": "Finnish", "no": "Norwegian", "da": "Danish",
}

var languageNativeNames = map[string]string{
	"ja": "日本語", "ko": "한국어", "zh": "中文", "zh-hans": "简体中文", "zh-hant": "繁體中文",
	"ar": "العربية", "he": "עברית", "hi": "हिन्दी", "ru": "Русский",
	"el": "Ελληνικά", "uk": "Українська", "tr": "Türkçe",
}

var sampleWords = map[string]string{
	"ja": "こんにちは", "ko": "안녕하세요", "zh": "你好", "zh-hans": "你好",
	"es": "hola", "fr": "bonjour", "de": "hallo", "it": "ciao",
	"pt": "olá", "ru": "привет", "tr": "merhaba", "ar": "مرحبا",
	"hi": "नमस्ते", "el": "γειά σου",
}
