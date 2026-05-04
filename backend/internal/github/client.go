package github

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"strings"
	"time"
)

const apiBase = "https://api.github.com"

// Client is a tiny GitHub REST client for what we need (latest release + asset download).
type Client struct {
	http  *http.Client
	token string // optional; raises rate limit and lets us read private repos
}

func New(token string) *Client {
	return &Client{
		http:  &http.Client{Timeout: 60 * time.Second},
		token: token,
	}
}

type Release struct {
	TagName string         `json:"tag_name"`
	Name    string         `json:"name"`
	Assets  []ReleaseAsset `json:"assets"`
}

type ReleaseAsset struct {
	Name        string `json:"name"`
	Size        int64  `json:"size"`
	ContentType string `json:"content_type"`
	URL         string `json:"url"`                  // API URL (use for download with Accept: octet-stream)
	BrowserURL  string `json:"browser_download_url"` // direct browser URL (no auth)
}

// ParseRepoURL accepts URLs like:
//
//	https://github.com/owner/repo
//	https://github.com/owner/repo.git
//	github.com/owner/repo
//
// and returns owner, repo.
func ParseRepoURL(raw string) (owner, repo string, err error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", "", fmt.Errorf("empty url")
	}
	if !strings.Contains(raw, "://") {
		raw = "https://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil {
		return "", "", fmt.Errorf("invalid url: %w", err)
	}
	if !strings.HasSuffix(u.Host, "github.com") {
		return "", "", fmt.Errorf("not a github.com url: %s", u.Host)
	}
	parts := strings.Split(strings.Trim(u.Path, "/"), "/")
	if len(parts) < 2 {
		return "", "", fmt.Errorf("expected /owner/repo path")
	}
	return parts[0], strings.TrimSuffix(parts[1], ".git"), nil
}

// LatestRelease fetches /repos/{owner}/{repo}/releases/latest.
func (c *Client) LatestRelease(ctx context.Context, owner, repo string) (*Release, error) {
	u := fmt.Sprintf("%s/repos/%s/%s/releases/latest", apiBase, owner, repo)
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	c.setHeaders(req)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("no releases found for %s/%s", owner, repo)
	}
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return nil, fmt.Errorf("github status %d: %s", resp.StatusCode, string(body))
	}
	var rel Release
	if err := json.NewDecoder(resp.Body).Decode(&rel); err != nil {
		return nil, err
	}
	return &rel, nil
}

// FindZipAsset returns the first .zip asset, preferring one whose name contains the repo name.
func FindZipAsset(rel *Release, repo string) *ReleaseAsset {
	var fallback *ReleaseAsset
	for i := range rel.Assets {
		a := &rel.Assets[i]
		if !strings.HasSuffix(strings.ToLower(a.Name), ".zip") {
			continue
		}
		if strings.Contains(strings.ToLower(a.Name), strings.ToLower(repo)) {
			return a
		}
		if fallback == nil {
			fallback = a
		}
	}
	return fallback
}

// DownloadAsset downloads a release asset by its API URL.
// Returns the bytes and the resolved filename.
func (c *Client) DownloadAsset(ctx context.Context, asset *ReleaseAsset, maxBytes int64) ([]byte, error) {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, asset.URL, nil)
	c.setHeaders(req)
	req.Header.Set("Accept", "application/octet-stream")
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("download status %d", resp.StatusCode)
	}
	if asset.Size > maxBytes {
		return nil, fmt.Errorf("asset size %d exceeds max %d", asset.Size, maxBytes)
	}
	return io.ReadAll(io.LimitReader(resp.Body, maxBytes+1))
}

func (c *Client) setHeaders(req *http.Request) {
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("User-Agent", "languageapp-backend")
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
}

// Hint extracts a short identifier from an asset name (used only for logs).
func Hint(asset *ReleaseAsset) string {
	return path.Base(asset.Name)
}
