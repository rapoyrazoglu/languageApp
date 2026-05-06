package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"golang.org/x/term"
)

// cmdLogin authenticates against a registry with email + password and saves
// the resulting JWT to the config file so subsequent commands can use it.
//
// Password is read from the terminal with echo disabled when stdin is a TTY,
// and from a single line otherwise (so scripts / CI can pipe it in via
// `echo $PASS | paktly login --email foo@bar`).
func cmdLogin(args []string) error {
	fs := flag.NewFlagSet("login", flag.ExitOnError)
	registryFlag := fs.String("registry", "", "registry base URL (default https://api.paktly.dev or saved config)")
	emailFlag := fs.String("email", "", "your account's email")
	fs.Usage = func() {
		fmt.Fprintln(os.Stderr, `paktly login — authenticate and persist a token

USAGE:
  paktly login [--email you@example.com] [--registry url]

If --email isn't provided, you'll be prompted. The password is always read
from the terminal (echo off when stdin is a TTY).`)
		fs.PrintDefaults()
	}
	if err := fs.Parse(args); err != nil {
		return err
	}

	cfg := resolveConfig()
	if *registryFlag != "" {
		cfg.Registry = *registryFlag
	}

	email := *emailFlag
	if email == "" {
		fmt.Print("Email: ")
		line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
		email = strings.TrimSpace(line)
	}
	if email == "" {
		return usageError("login: email is required")
	}

	password, err := readPassword()
	if err != nil {
		return err
	}
	if password == "" {
		return usageError("login: password is required")
	}

	token, err := loginToRegistry(cfg.Registry, email, password)
	if err != nil {
		return err
	}

	cfg.Token = token
	if err := saveConfigFile(cfg); err != nil {
		return fmt.Errorf("save config: %w", err)
	}
	fmt.Println("logged in. Token saved to", configPath())
	return nil
}

func readPassword() (string, error) {
	fmt.Print("Password: ")
	defer fmt.Println()

	if term.IsTerminal(int(os.Stdin.Fd())) {
		bytes, err := term.ReadPassword(int(os.Stdin.Fd()))
		if err != nil {
			return "", fmt.Errorf("read password: %w", err)
		}
		return string(bytes), nil
	}
	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil && line == "" {
		return "", fmt.Errorf("read password: %w", err)
	}
	return strings.TrimRight(line, "\n\r"), nil
}

func loginToRegistry(registry, email, password string) (string, error) {
	url := strings.TrimRight(registry, "/") + "/v1/auth/login"
	body, err := json.Marshal(map[string]string{"email": email, "password": password})
	if err != nil {
		return "", err
	}
	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("login request: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == http.StatusOK {
		var ok struct {
			Token string `json:"token"`
		}
		if err := json.Unmarshal(respBody, &ok); err != nil || ok.Token == "" {
			return "", fmt.Errorf("decode login: %w (body: %s)", err, truncate(respBody, 200))
		}
		return ok.Token, nil
	}

	var envelope APIErrorBody
	if err := json.Unmarshal(respBody, &envelope); err == nil && envelope.Error.Code != "" {
		return "", &cliError{
			msg:  fmt.Sprintf("login rejected (%d %s): %s", resp.StatusCode, envelope.Error.Code, envelope.Error.Message),
			code: 1,
		}
	}
	return "", &cliError{
		msg:  fmt.Sprintf("login HTTP %d (body: %s)", resp.StatusCode, truncate(respBody, 400)),
		code: 1,
	}
}
