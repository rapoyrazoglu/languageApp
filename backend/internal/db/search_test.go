package db

import (
	"testing"
	"time"
)

func TestCursor_RoundTrip(t *testing.T) {
	now := time.Date(2026, 1, 2, 3, 4, 5, 678901234, time.UTC)
	c := encodeCursor(now, "com.github.user.pack")
	if c == "" {
		t.Fatal("empty cursor")
	}
	gotTime, gotID, err := decodeCursor(c)
	if err != nil {
		t.Fatal(err)
	}
	if !gotTime.Equal(now) {
		t.Fatalf("time mismatch: %v vs %v", gotTime, now)
	}
	if gotID != "com.github.user.pack" {
		t.Fatalf("id mismatch: %q", gotID)
	}
}

func TestCursor_RejectsGarbage(t *testing.T) {
	cases := []string{
		"not-base64!!",
		"YQ", // valid base64 of "a" but wrong format
		"",
	}
	for _, c := range cases {
		if _, _, err := decodeCursor(c); err == nil && c != "" {
			t.Errorf("expected error for cursor %q", c)
		}
	}
}
