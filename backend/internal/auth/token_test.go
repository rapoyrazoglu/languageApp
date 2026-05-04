package auth

import (
	"errors"
	"strings"
	"testing"
	"time"
)

const testSecret = "0123456789abcdef0123456789abcdef" // 32 bytes

func TestNewIssuer_RejectsShortSecret(t *testing.T) {
	if _, err := NewIssuer("short", time.Hour); err == nil {
		t.Fatal("expected error for short secret")
	}
}

func TestIssue_VerifyRoundTrip(t *testing.T) {
	iss, err := NewIssuer(testSecret, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	tok, exp, err := iss.Issue("user-1", "u@example.com")
	if err != nil {
		t.Fatal(err)
	}
	if !exp.After(time.Now()) {
		t.Fatal("expiry should be in the future")
	}
	claims, err := iss.Verify(tok)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if claims.UserID != "user-1" || claims.Email != "u@example.com" {
		t.Fatalf("unexpected claims: %+v", claims)
	}
}

func TestVerify_RejectsTamperedSignature(t *testing.T) {
	iss, _ := NewIssuer(testSecret, time.Hour)
	tok, _, _ := iss.Issue("user-1", "")

	// Flip last char of the signature.
	parts := strings.Split(tok, ".")
	if len(parts) != 3 {
		t.Fatalf("expected 3 jwt parts, got %d", len(parts))
	}
	parts[2] = flipLast(parts[2])
	tampered := strings.Join(parts, ".")

	if _, err := iss.Verify(tampered); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("expected ErrTokenInvalid, got %v", err)
	}
}

func TestVerify_RejectsExpired(t *testing.T) {
	// Mint with a tiny TTL by constructing an issuer that bypasses the default.
	// We use a microsecond TTL — by the time Verify runs, exp is in the past.
	iss, _ := NewIssuer(testSecret, time.Microsecond)
	tok, _, _ := iss.Issue("user-1", "")
	time.Sleep(10 * time.Millisecond)

	_, err := iss.Verify(tok)
	if !errors.Is(err, ErrTokenExpired) {
		t.Fatalf("expected ErrTokenExpired, got %v", err)
	}
}

func TestVerify_RejectsWrongSecret(t *testing.T) {
	a, _ := NewIssuer(testSecret, time.Hour)
	b, _ := NewIssuer("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", time.Hour)
	tok, _, _ := a.Issue("user-1", "")
	if _, err := b.Verify(tok); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("expected ErrTokenInvalid, got %v", err)
	}
}

func flipLast(s string) string {
	if s == "" {
		return s
	}
	c := s[len(s)-1]
	if c == 'A' {
		c = 'B'
	} else {
		c = 'A'
	}
	return s[:len(s)-1] + string(c)
}
