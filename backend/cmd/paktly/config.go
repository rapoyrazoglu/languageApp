package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
)

// config persists the user's preferred registry + auth token between
// command invocations so they don't have to pass --token on every publish.
//
// Stored at $XDG_CONFIG_HOME/paktly/config.json (defaults to
// ~/.config/paktly/config.json). The file is chmod 0600 because it holds
// a JWT — leaking it would let anyone publish under the user's account.
type config struct {
	Registry string `json:"registry,omitempty"`
	Token    string `json:"token,omitempty"`
}

const defaultRegistry = "https://api.paktly.dev"

// resolveConfig folds env vars + config file into a single value. Flags are
// applied by each subcommand on top of this base.
func resolveConfig() config {
	cfg := loadConfigFile()
	if env := os.Getenv("PAKTLY_REGISTRY"); env != "" {
		cfg.Registry = env
	}
	if env := os.Getenv("PAKTLY_TOKEN"); env != "" {
		cfg.Token = env
	}
	if cfg.Registry == "" {
		cfg.Registry = defaultRegistry
	}
	return cfg
}

func loadConfigFile() config {
	path := configPath()
	data, err := os.ReadFile(path)
	if err != nil {
		return config{}
	}
	var c config
	_ = json.Unmarshal(data, &c)
	return c
}

func saveConfigFile(c config) error {
	path := configPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	// 0600 — only the user can read; the file holds an auth token.
	return os.WriteFile(path, data, 0o600)
}

func configPath() string {
	if x := os.Getenv("XDG_CONFIG_HOME"); x != "" {
		return filepath.Join(x, "paktly", "config.json")
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ".paktly-config.json"
	}
	return filepath.Join(home, ".config", "paktly", "config.json")
}

// requireToken returns the resolved token or an error suitable for direct
// stderr reporting. Used by `pack publish` and any other auth-gated command.
func requireToken(c config) (string, error) {
	if c.Token != "" {
		return c.Token, nil
	}
	return "", errors.New("no auth token. Run `paktly login` or set PAKTLY_TOKEN")
}
