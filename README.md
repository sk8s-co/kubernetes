# Kubernetes Stack Bundle

Lightweight bundle of the binaries needed to stand up a minimal Kubernetes control plane. Instead of shipping a full etcd, the repo provides an embedded etcd binary to keep local and CI usage small and fast.

## What’s Included

- Embedded etcd binary built from `cmd/etcd` (single-node, dev-friendly defaults).
- Kubernetes control-plane binaries: `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, and `kubectl`.
- `Procfile` to orchestrate the processes together via `procfiled`.
- Self-signed TLS and service account keys generated during the Docker build for local usage.

## Quick Start

```sh
docker compose up          # build image and expose API server on 8080
# or build directly
docker build -t sk8s-kubernetes .
docker run --rm -p 8080:8080 sk8s-kubernetes
```

Once running, talk to the API server on `http://localhost:8080` with `kubectl` (insecure/anonymous by default).

## Development

```sh
go run ./cmd/etcd          # start embedded etcd locally
go build ./cmd/etcd        # compile the embedded etcd binary
go test ./...              # execute Go tests (if added)
```

The embedded etcd writes to `/tmp/etcd-data`; mount a volume if you need persistence. Adjust control-plane flags in `Procfile` instead of editing binaries.

## Notes

- Generated certs (`tls.crt`, `tls.key`, `sa.key`, `sa.pub`) are for local/dev only; replace for any real deployment.
- Images pin Kubernetes `v1.34.0` and etcd `v3.6.6`; update the `Dockerfile` ARGs to bump versions.
- Repo is private; the published container image on GHCR is public for consumers.
- For project contribution details, see `AGENTS.md`.
