# Repository Guidelines

## Project Structure & Module Organization

- Repo bundles all binaries needed for a minimal Kubernetes stack; etcd is replaced with an embedded variant for lighter weight and simpler local use.
- Go module root lives at `go.mod`; primary entry point is `cmd/etcd/main.go`, which boots a single-node embedded etcd and seeds a `started-at` key.
- Container build is defined in `Dockerfile` (multi-stage: compile static embedded `etcd`, validate binaries, bake certs, assemble runtime image with `procfiled`).
- Runtime process layout is in `Procfile`; `docker-compose.yml` exposes the bundled stack on `8080`.
- Generated TLS assets and service account keys are produced during the Docker build; local runs rely on temp dirs (`/tmp/etcd-data` by default).

## Build, Test, and Development Commands

- `go build ./cmd/etcd` — compile the embedded etcd binary locally.
- `go run ./cmd/etcd` — start etcd with the repo defaults; watch logs for readiness before hitting `127.0.0.1:2379`.
- `go test ./...` — run all Go unit tests (none yet, but keep green as tests are added).
- `docker build -t sk8s-kubernetes .` — produce the runtime image with prebuilt control-plane binaries and generated certs.
- `docker compose up` — start the containerized stack and expose the API server on `8080`.

## Coding Style & Naming Conventions

- Use `gofmt`/`goimports` on all Go files; default Go indentation (tabs) and `golangci-lint`-friendly patterns if introduced later.
- Package and variable names should be lower_snake for files, camelCase for locals, and PascalCase for exported identifiers; keep package names short and purpose-driven.
- Keep configuration literals near their usage; avoid global state except for immutable defaults.

## Testing Guidelines

- Prefer table-driven tests; colocate `_test.go` files with the code under test in `cmd/` or future `pkg/` dirs.
- When touching client interactions, add timeouts to contexts and assert error paths.
- Include smoke checks for Dockerized flows via `docker run --rm sk8s-kubernetes etcd version` if adding release steps.

## Container & Runtime Notes

- The runtime image uses generated self-signed certs; replace `tls.crt/tls.key` with real material for any non-local use.
- Embedded etcd keeps state in `/tmp/etcd-data` when run locally; mount a volume if persistence is needed, or swap to a remote etcd only if full-weight clusters are required.
- `Procfile` starts embedded etcd and kube components together; adjust flags there rather than editing binaries.

## Commit & Pull Request Guidelines

- Use concise, imperative commit subjects (e.g., `Add embedded etcd startup guard`); keep body lines wrapped and explain rationale plus impacts.
- Reference related issues in commit bodies or PR descriptions; include reproduction steps or `go test ./...` / `docker build ...` results.
- PRs should summarize scope, note config changes (ports, paths, flags), and attach logs or screenshots when modifying runtime behavior.
