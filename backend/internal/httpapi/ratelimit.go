package httpapi

import (
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// RateLimiter is an in-memory token-bucket limiter per "subject".
//
// The subject is the user id when the request is authenticated (Bearer token
// verifies), or the client IP otherwise. Authed users get a higher quota since
// they are accountable.
//
// This is intentionally simple — fits a single-instance backend. For a
// multi-instance setup, swap with a shared store (Redis / Postgres advisory
// locks). The Wrap signature stays the same.
type RateLimiter struct {
	anonPerMinute  int
	userPerMinute  int
	verifyToken    func(string) (userID string, ok bool)
	mu             sync.Mutex
	buckets        map[string]*bucket
	cleanupRunning bool
}

type bucket struct {
	tokens   float64
	capacity float64
	rate     float64 // tokens per second
	last     time.Time
}

// NewRateLimiter creates a limiter with separate quotas for anonymous and
// authenticated subjects. verifyToken should validate the bearer and return
// the user id; if it returns ok=false the request is treated as anonymous.
func NewRateLimiter(anonPerMinute, userPerMinute int, verifyToken func(string) (string, bool)) *RateLimiter {
	if anonPerMinute <= 0 {
		anonPerMinute = 60
	}
	if userPerMinute <= 0 {
		userPerMinute = 600
	}
	return &RateLimiter{
		anonPerMinute: anonPerMinute,
		userPerMinute: userPerMinute,
		verifyToken:   verifyToken,
		buckets:       make(map[string]*bucket),
	}
}

// Wrap returns an http.Handler that consumes a token from the caller's bucket
// before forwarding. On exhaustion, returns 429 with Retry-After.
func (l *RateLimiter) Wrap(next http.Handler) http.Handler {
	l.startCleanupOnce()
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		subject, capacity, rate := l.classify(r)
		retryAfter, allowed := l.allow(subject, capacity, rate)
		if !allowed {
			seconds := int(retryAfter.Seconds() + 0.999)
			if seconds < 1 {
				seconds = 1
			}
			w.Header().Set("Retry-After", strconv.Itoa(seconds))
			writeAPIError(w, http.StatusTooManyRequests, CodeRateLimited,
				"rate limit exceeded; retry after "+strconv.Itoa(seconds)+"s")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (l *RateLimiter) classify(r *http.Request) (subject string, capacity, rate float64) {
	if l.verifyToken != nil {
		if tok := bearerToken(r); tok != "" {
			if uid, ok := l.verifyToken(tok); ok {
				return "u:" + uid,
					float64(l.userPerMinute),
					float64(l.userPerMinute) / 60.0
			}
		}
	}
	return "ip:" + clientIP(r),
		float64(l.anonPerMinute),
		float64(l.anonPerMinute) / 60.0
}

func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		// First entry is the original client (when behind a trusted proxy).
		if i := strings.IndexByte(xff, ','); i > 0 {
			return strings.TrimSpace(xff[:i])
		}
		return strings.TrimSpace(xff)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func (l *RateLimiter) allow(subject string, capacity, rate float64) (time.Duration, bool) {
	now := time.Now()

	l.mu.Lock()
	defer l.mu.Unlock()

	b, ok := l.buckets[subject]
	if !ok {
		b = &bucket{tokens: capacity, capacity: capacity, rate: rate, last: now}
		l.buckets[subject] = b
	} else {
		// Refill since last visit.
		elapsed := now.Sub(b.last).Seconds()
		b.tokens += elapsed * b.rate
		if b.tokens > b.capacity {
			b.tokens = b.capacity
		}
		b.last = now
		// Quota change (e.g. user upgraded) is ignored; capacity/rate are sticky
		// per bucket — fine for our use.
	}

	if b.tokens >= 1.0 {
		b.tokens -= 1.0
		return 0, true
	}
	needed := 1.0 - b.tokens
	wait := time.Duration(needed/b.rate*1000) * time.Millisecond
	return wait, false
}

// startCleanupOnce kicks off a janitor that drops idle buckets so memory does
// not grow without bound. Idempotent.
func (l *RateLimiter) startCleanupOnce() {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.cleanupRunning {
		return
	}
	l.cleanupRunning = true
	go func() {
		for range time.Tick(5 * time.Minute) {
			cutoff := time.Now().Add(-15 * time.Minute)
			l.mu.Lock()
			for k, b := range l.buckets {
				if b.last.Before(cutoff) {
					delete(l.buckets, k)
				}
			}
			l.mu.Unlock()
		}
	}()
}
