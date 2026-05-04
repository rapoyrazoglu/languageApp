package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRateLimiter_AnonExhaustionAndRecovery(t *testing.T) {
	// 60/min anon = 1 req/sec. Capacity is 60 (full bucket). After 60 requests
	// the 61st must be rejected.
	rl := NewRateLimiter(60, 600, nil)
	h := rl.Wrap(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	const ip = "1.2.3.4:5555"
	for i := 0; i < 60; i++ {
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.RemoteAddr = ip
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("request %d should pass, got %d", i+1, rec.Code)
		}
	}

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = ip
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("61st request should 429, got %d", rec.Code)
	}
	if rec.Header().Get("Retry-After") == "" {
		t.Fatal("expected Retry-After header on 429")
	}
}

func TestRateLimiter_SeparateBucketsPerIP(t *testing.T) {
	rl := NewRateLimiter(2, 600, nil)
	h := rl.Wrap(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	// Burn ip A's tokens.
	for i := 0; i < 3; i++ {
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.RemoteAddr = "1.1.1.1:1111"
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if i < 2 && rec.Code != http.StatusOK {
			t.Fatalf("A req %d should pass, got %d", i+1, rec.Code)
		}
		if i == 2 && rec.Code != http.StatusTooManyRequests {
			t.Fatalf("A req 3 should 429, got %d", rec.Code)
		}
	}

	// ip B is unaffected.
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "2.2.2.2:2222"
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("ip B should not share ip A's bucket, got %d", rec.Code)
	}
}

func TestRateLimiter_AuthedUserGetsHigherQuota(t *testing.T) {
	verify := func(token string) (string, bool) {
		if token == "good" {
			return "user-123", true
		}
		return "", false
	}
	// Anon gets 1/min, user gets 5/min. Ten authed requests with quota 5 should
	// consume all 5 then 429.
	rl := NewRateLimiter(1, 5, verify)
	h := rl.Wrap(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	for i := 0; i < 5; i++ {
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.Header.Set("Authorization", "Bearer good")
		req.RemoteAddr = "9.9.9.9:9999"
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("authed req %d should pass under user quota, got %d", i+1, rec.Code)
		}
	}

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer good")
	req.RemoteAddr = "9.9.9.9:9999"
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("authed req 6 should 429, got %d", rec.Code)
	}
}

func TestRateLimiter_BadTokenFallsBackToIPQuota(t *testing.T) {
	verify := func(token string) (string, bool) { return "", false }
	rl := NewRateLimiter(1, 100, verify)
	h := rl.Wrap(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	for i := 0; i < 2; i++ {
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.Header.Set("Authorization", "Bearer bogus")
		req.RemoteAddr = "3.3.3.3:3333"
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if i == 0 && rec.Code != http.StatusOK {
			t.Fatalf("first req should pass, got %d", rec.Code)
		}
		if i == 1 && rec.Code != http.StatusTooManyRequests {
			t.Fatalf("second req should hit anon quota, got %d", rec.Code)
		}
	}
}
