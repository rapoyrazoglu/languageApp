package auth

import (
	"errors"
	"fmt"
	"unicode/utf8"

	"golang.org/x/crypto/bcrypt"
)

// MinPasswordLength is enforced at registration time.
const MinPasswordLength = 8

// MaxPasswordBytes is the bcrypt hard limit. Inputs longer than this are
// silently truncated by bcrypt, which is a footgun — we reject up front.
const MaxPasswordBytes = 72

var (
	ErrPasswordTooShort = fmt.Errorf("password must be at least %d characters", MinPasswordLength)
	ErrPasswordTooLong  = fmt.Errorf("password must be at most %d bytes", MaxPasswordBytes)
	ErrInvalidPassword  = errors.New("invalid email or password")
)

// HashPassword returns a bcrypt hash safe to store.
func HashPassword(plain string) (string, error) {
	if utf8.RuneCountInString(plain) < MinPasswordLength {
		return "", ErrPasswordTooShort
	}
	if len(plain) > MaxPasswordBytes {
		return "", ErrPasswordTooLong
	}
	h, err := bcrypt.GenerateFromPassword([]byte(plain), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(h), nil
}

// CheckPassword compares a plain-text password against a stored bcrypt hash.
// Returns ErrInvalidPassword for any mismatch (intentionally generic).
func CheckPassword(hash, plain string) error {
	if len(plain) > MaxPasswordBytes {
		return ErrInvalidPassword
	}
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(plain)); err != nil {
		return ErrInvalidPassword
	}
	return nil
}
