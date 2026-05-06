package main

import (
	"reflect"
	"testing"
)

func TestReorderArgs_FlagsBeforePositional_Untouched(t *testing.T) {
	got := reorderArgs([]string{"--id", "x", "--name", "y", "slug"}, nil)
	want := []string{"--id", "x", "--name", "y", "slug"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
}

func TestReorderArgs_PositionalFirst_GetsMovedToEnd(t *testing.T) {
	got := reorderArgs([]string{"slug", "--id", "x", "--name", "y"}, nil)
	want := []string{"--id", "x", "--name", "y", "slug"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
}

func TestReorderArgs_PositionalInMiddle_GetsMovedToEnd(t *testing.T) {
	got := reorderArgs([]string{"--id", "x", "slug", "--name", "y"}, nil)
	want := []string{"--id", "x", "--name", "y", "slug"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
}

func TestReorderArgs_BoolFlag_DoesntConsumeNextArg(t *testing.T) {
	// `--json` is bool — the following "/path" must NOT be paired with it.
	got := reorderArgs([]string{"--json", "/path"}, []string{"json"})
	want := []string{"--json", "/path"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
}

func TestReorderArgs_InlineEqualsValue_NotConsumeNext(t *testing.T) {
	got := reorderArgs([]string{"--id=foo", "slug"}, nil)
	want := []string{"--id=foo", "slug"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
}

func TestReorderArgs_BoolFlagInMiddle_PositionalAfterMoved(t *testing.T) {
	// `pack publish ./pack --skip-validate` must reorder to
	// `--skip-validate ./pack` so flag.Parse sees the bool first.
	got := reorderArgs([]string{"./pack", "--skip-validate"}, []string{"skip-validate"})
	want := []string{"--skip-validate", "./pack"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
}
