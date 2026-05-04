.PHONY: up down logs psql migrate-up migrate-down run tidy build test test-integration

up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f

psql:
	docker compose exec postgres psql -U langapp -d langapp

migrate-up:
	goose -dir migrations postgres "$$DATABASE_URL" up

migrate-down:
	goose -dir migrations postgres "$$DATABASE_URL" down

run:
	go run ./cmd/api

build:
	go build -o bin/api ./cmd/api

tidy:
	go mod tidy

test:
	go test ./...

# Integration tests need a running Postgres + MinIO (see docker-compose.yml).
# Schemas are wiped on each run, so this is destructive against the configured DB.
test-integration:
	go test -tags=integration -count=1 -timeout=120s ./integration/...
