package httpapi

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"testing"
)

func TestVerifyGitHubSignature(t *testing.T) {
	secret := "topsecret"
	body := []byte(`{"action":"published"}`)

	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	good := "sha256=" + hex.EncodeToString(mac.Sum(nil))

	tests := []struct {
		name   string
		header string
		secret string
		want   bool
	}{
		{"valid", good, secret, true},
		{"wrong secret", good, "other", false},
		{"missing prefix", hex.EncodeToString(mac.Sum(nil)), secret, false},
		{"empty header", "", secret, false},
		{"bad hex", "sha256=zzz", secret, false},
		{"truncated", "sha256=" + hex.EncodeToString(mac.Sum(nil))[:10], secret, false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := verifyGitHubSignature(tc.header, tc.secret, body)
			if got != tc.want {
				t.Fatalf("want %v, got %v", tc.want, got)
			}
		})
	}
}

func TestReleaseActionTriggersIngest(t *testing.T) {
	yes := []string{"published", "released", "created"}
	no := []string{"deleted", "edited", "prereleased", ""}
	for _, a := range yes {
		if !releaseActionTriggersIngest(a) {
			t.Fatalf("expected %q to trigger", a)
		}
	}
	for _, a := range no {
		if releaseActionTriggersIngest(a) {
			t.Fatalf("expected %q not to trigger", a)
		}
	}
}
