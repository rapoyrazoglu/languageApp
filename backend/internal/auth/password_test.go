package auth

import (
	"errors"
	"strings"
	"testing"
)

func TestHashPassword_RejectsShort(t *testing.T) {
	_, err := HashPassword("short")
	if !errors.Is(err, ErrPasswordTooShort) {
		t.Fatalf("expected ErrPasswordTooShort, got %v", err)
	}
}

func TestHashPassword_RejectsLong(t *testing.T) {
	long := strings.Repeat("a", MaxPasswordBytes+1)
	_, err := HashPassword(long)
	if !errors.Is(err, ErrPasswordTooLong) {
		t.Fatalf("expected ErrPasswordTooLong, got %v", err)
	}
}

func TestHashPassword_RoundTrip(t *testing.T) {
	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatal(err)
	}
	if hash == "" {
		t.Fatal("empty hash")
	}
	if err := CheckPassword(hash, "correct horse battery staple"); err != nil {
		t.Fatalf("expected match, got %v", err)
	}
}

func TestCheckPassword_WrongIsGenericError(t *testing.T) {
	hash, _ := HashPassword("right password 123")
	err := CheckPassword(hash, "wrong password 123")
	if !errors.Is(err, ErrInvalidPassword) {
		t.Fatalf("expected ErrInvalidPassword, got %v", err)
	}
}

func TestCheckPassword_OverlongInputDoesNotMatch(t *testing.T) {
	// bcrypt silently truncates >72 bytes — ensure our wrapper rejects up front
	// so an attacker cannot brute-force the truncated suffix.
	hash, _ := HashPassword("right password 123")
	overlong := strings.Repeat("x", MaxPasswordBytes+1)
	if err := CheckPassword(hash, overlong); !errors.Is(err, ErrInvalidPassword) {
		t.Fatalf("expected ErrInvalidPassword for overlong input, got %v", err)
	}
}

func TestHashPassword_UTF8Counted(t *testing.T) {
	// "köprü" — 5 runes but more than 5 bytes. Should pass the rune-count check.
	hash, err := HashPassword("köprü123")
	if err != nil {
		t.Fatalf("UTF-8 8-rune password should be accepted, got %v", err)
	}
	if err := CheckPassword(hash, "köprü123"); err != nil {
		t.Fatalf("UTF-8 round trip failed: %v", err)
	}
}
