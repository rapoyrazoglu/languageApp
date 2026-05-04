package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	HTTPAddr string

	DatabaseURL string

	S3Endpoint     string
	S3Region       string
	S3Bucket       string
	S3AccessKey    string
	S3SecretKey    string
	S3UsePathStyle bool

	GitHubToken         string
	GitHubWebhookSecret string

	JWTSecret   string
	JWTTTLHours int

	MaxPackSizeBytes int64

	RateLimitAnonPerMinute int
	RateLimitUserPerMinute int
}

func Load() (*Config, error) {
	c := &Config{
		HTTPAddr:            getEnv("HTTP_ADDR", ":8080"),
		DatabaseURL:         os.Getenv("DATABASE_URL"),
		S3Endpoint:          os.Getenv("S3_ENDPOINT"),
		S3Region:            getEnv("S3_REGION", "us-east-1"),
		S3Bucket:            getEnv("S3_BUCKET", "packs"),
		S3AccessKey:         os.Getenv("S3_ACCESS_KEY"),
		S3SecretKey:         os.Getenv("S3_SECRET_KEY"),
		S3UsePathStyle:      getEnvBool("S3_USE_PATH_STYLE", true),
		GitHubToken:         os.Getenv("GITHUB_TOKEN"),
		GitHubWebhookSecret: os.Getenv("GITHUB_WEBHOOK_SECRET"),
		JWTSecret:           os.Getenv("JWT_SECRET"),
	}

	maxSize, err := strconv.ParseInt(getEnv("MAX_PACK_SIZE_BYTES", "524288000"), 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid MAX_PACK_SIZE_BYTES: %w", err)
	}
	c.MaxPackSizeBytes = maxSize

	ttl, err := strconv.Atoi(getEnv("JWT_TTL_HOURS", "24"))
	if err != nil {
		return nil, fmt.Errorf("invalid JWT_TTL_HOURS: %w", err)
	}
	c.JWTTTLHours = ttl

	anon, err := strconv.Atoi(getEnv("RATE_LIMIT_ANON_PER_MIN", "60"))
	if err != nil {
		return nil, fmt.Errorf("invalid RATE_LIMIT_ANON_PER_MIN: %w", err)
	}
	c.RateLimitAnonPerMinute = anon

	user, err := strconv.Atoi(getEnv("RATE_LIMIT_USER_PER_MIN", "600"))
	if err != nil {
		return nil, fmt.Errorf("invalid RATE_LIMIT_USER_PER_MIN: %w", err)
	}
	c.RateLimitUserPerMinute = user

	if c.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}
	if c.S3Bucket == "" {
		return nil, fmt.Errorf("S3_BUCKET is required")
	}
	// S3 endpoint + credentials are optional:
	//  - On AWS, leave them empty so the SDK uses the default credential chain
	//    (IAM instance role / env / profile) and the default S3 endpoint.
	//  - For MinIO/R2/etc., set all three (endpoint + access + secret).
	if len(c.JWTSecret) < 32 {
		return nil, fmt.Errorf("JWT_SECRET must be at least 32 characters")
	}

	return c, nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvBool(key string, fallback bool) bool {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return fallback
	}
	return b
}
