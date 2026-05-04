package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/ata/languageapp/backend/internal/auth"
	"github.com/ata/languageapp/backend/internal/config"
	"github.com/ata/languageapp/backend/internal/db"
	"github.com/ata/languageapp/backend/internal/github"
	"github.com/ata/languageapp/backend/internal/httpapi"
	"github.com/ata/languageapp/backend/internal/pack"
	"github.com/ata/languageapp/backend/internal/storage"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	if err := run(logger); err != nil {
		logger.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	database, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer database.Close()
	logger.Info("db connected")

	store, err := storage.New(ctx, storage.Config{
		Endpoint:     cfg.S3Endpoint,
		Region:       cfg.S3Region,
		Bucket:       cfg.S3Bucket,
		AccessKey:    cfg.S3AccessKey,
		SecretKey:    cfg.S3SecretKey,
		UsePathStyle: cfg.S3UsePathStyle,
	})
	if err != nil {
		return err
	}
	logger.Info("storage ready", "bucket", cfg.S3Bucket)

	validator, err := pack.NewValidator()
	if err != nil {
		return err
	}

	ingester := &pack.Ingester{
		Validator: validator,
		Storage:   store,
		Sink:      &db.Adapter{DB: database},
	}

	gh := github.New(cfg.GitHubToken)

	tokens, err := auth.NewIssuer(cfg.JWTSecret, time.Duration(cfg.JWTTTLHours)*time.Hour)
	if err != nil {
		return err
	}

	limiter := httpapi.NewRateLimiter(
		cfg.RateLimitAnonPerMinute,
		cfg.RateLimitUserPerMinute,
		func(token string) (string, bool) {
			claims, err := tokens.Verify(token)
			if err != nil {
				return "", false
			}
			return claims.UserID, true
		},
	)

	srv := httpapi.NewServer(httpapi.Deps{
		Logger:        logger,
		DB:            database,
		Storage:       store,
		Ingester:      ingester,
		GitHub:        gh,
		Tokens:        tokens,
		MaxPackSize:   cfg.MaxPackSizeBytes,
		Limiter:       limiter,
		WebhookSecret: cfg.GitHubWebhookSecret,
	})

	httpServer := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		logger.Info("listening", "addr", cfg.HTTPAddr)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("http server", "err", err)
			stop()
		}
	}()

	<-ctx.Done()
	logger.Info("shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return httpServer.Shutdown(shutdownCtx)
}
