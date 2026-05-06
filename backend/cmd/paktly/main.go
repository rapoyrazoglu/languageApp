// Command paktly is the creator-side CLI: scaffold a new pack, validate it
// locally before upload, and publish it to a paktly-compatible registry.
//
// Usage:
//
//	paktly pack new <slug> [flags]
//	paktly pack validate <path>
//	paktly pack publish <path> [--registry url] [--token token]
//	paktly login
//	paktly version
//	paktly help
//
// Configuration precedence (highest first):
//
//  1. Command-line flags (--registry, --token).
//  2. Environment variables (PAKTLY_REGISTRY, PAKTLY_TOKEN).
//  3. Config file at $XDG_CONFIG_HOME/paktly/config.json (or
//     ~/.config/paktly/config.json on macOS / Linux).
//
// The CLI exits with status 0 on success, 2 on usage errors, and 1 on
// runtime failures. Validation failures exit with 2 and print each error
// on its own line so editors and CI can surface them inline.
package main

import (
	"fmt"
	"os"
)

const cliVersion = "0.3.0"

func main() {
	if len(os.Args) < 2 {
		printRootUsage()
		os.Exit(2)
	}
	switch os.Args[1] {
	case "pack":
		runPackSubcommand(os.Args[2:])
	case "login":
		exitOnError(cmdLogin(os.Args[2:]))
	case "version", "--version", "-v":
		fmt.Println("paktly", cliVersion)
	case "help", "--help", "-h":
		printRootUsage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n\n", os.Args[1])
		printRootUsage()
		os.Exit(2)
	}
}

func runPackSubcommand(args []string) {
	if len(args) == 0 {
		printPackUsage()
		os.Exit(2)
	}
	switch args[0] {
	case "new":
		exitOnError(cmdPackNew(args[1:]))
	case "validate":
		exitOnError(cmdPackValidate(args[1:]))
	case "publish":
		exitOnError(cmdPackPublish(args[1:]))
	case "help", "--help", "-h":
		printPackUsage()
	default:
		fmt.Fprintf(os.Stderr, "unknown pack subcommand: %s\n\n", args[0])
		printPackUsage()
		os.Exit(2)
	}
}

func printRootUsage() {
	fmt.Fprintln(os.Stderr, `paktly — language pack toolkit

USAGE:
  paktly <command> [arguments]

COMMANDS:
  pack new <slug>          Scaffold a new pack folder ready to edit + publish
  pack validate <path>     Run the registry's validator on a folder or zip
  pack publish <path>      Upload a pack to the registry (auth required)
  login                    Authenticate against a registry and persist the token
  version                  Print CLI version
  help                     Show this help

EXAMPLES:
  paktly pack new my-japanese-pack
  paktly pack validate ./my-japanese-pack
  paktly pack publish ./my-japanese-pack

  PAKTLY_REGISTRY=https://api.paktly.dev \
  PAKTLY_TOKEN=<jwt> paktly pack publish ./my-pack

DOCS: https://github.com/rapoyrazoglu/languageApp/blob/main/docs/AUTHORING.md`)
}

func printPackUsage() {
	fmt.Fprintln(os.Stderr, `paktly pack — manage a single pack

USAGE:
  paktly pack <subcommand> [arguments]

SUBCOMMANDS:
  new <slug>          Scaffold a new pack folder
  validate <path>     Validate a folder or .zip without uploading
  publish <path>      Upload a folder or .zip to the registry

Run 'paktly pack <subcommand> --help' for subcommand-specific options.`)
}

// exitOnError reports the error to stderr and exits the process with code 1
// (or whatever the error carries via *cliError). Keeps every command's
// happy path linear by absorbing all the boilerplate.
func exitOnError(err error) {
	if err == nil {
		return
	}
	if ce, ok := err.(*cliError); ok {
		fmt.Fprintln(os.Stderr, ce.msg)
		os.Exit(ce.code)
	}
	fmt.Fprintln(os.Stderr, "error:", err)
	os.Exit(1)
}

// cliError carries an exit code alongside the error message. Used for cases
// where we want a non-1 exit (e.g. validation failures exit 2 so editors can
// distinguish "tool blew up" from "your pack has issues").
type cliError struct {
	msg  string
	code int
}

func (e *cliError) Error() string { return e.msg }

func usageError(format string, args ...any) error {
	return &cliError{msg: fmt.Sprintf(format, args...), code: 2}
}

// reorderArgs moves positional arguments to the end so stdlib `flag` can
// parse them when they're sprinkled between flags. Callers pass the list of
// boolean flag names so we know not to consume the following arg as a value.
//
// Without this, `paktly pack new my-pack --id ...` puts everything from
// "my-pack" onward into Args(), since flag.Parse stops at the first
// non-flag token.
func reorderArgs(args []string, boolFlags []string) []string {
	boolSet := make(map[string]struct{}, len(boolFlags))
	for _, f := range boolFlags {
		boolSet[f] = struct{}{}
	}

	flagName := func(arg string) (name string, isBool bool) {
		trimmed := arg
		for len(trimmed) > 0 && trimmed[0] == '-' {
			trimmed = trimmed[1:]
		}
		// Drop trailing `=value` if present.
		for i, ch := range trimmed {
			if ch == '=' {
				trimmed = trimmed[:i]
				break
			}
		}
		_, isBool = boolSet[trimmed]
		return trimmed, isBool
	}

	var flags, positional []string
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if len(arg) == 0 || arg[0] != '-' {
			positional = append(positional, arg)
			continue
		}
		flags = append(flags, arg)
		// "--key=value" or "--bool" — no separate value to consume.
		hasInline := false
		for _, ch := range arg {
			if ch == '=' {
				hasInline = true
				break
			}
		}
		if hasInline {
			continue
		}
		_, isBool := flagName(arg)
		if isBool {
			continue
		}
		// Consume the next arg as this flag's value.
		if i+1 < len(args) {
			flags = append(flags, args[i+1])
			i++
		}
	}
	return append(flags, positional...)
}
