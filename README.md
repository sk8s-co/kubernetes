# Kubernetes Stack Bundle

Minimal bundle of Kubernetes control plane binaries, with patches for serverless environments.

## What's Included

- `etcd`
- `etcdctl`
- `kube-apiserver`
- `kube-controller-manager`
- `kube-scheduler`
- `kubectl`
- `kubelet` (built from source with patches)

## Patches

The `kubelet` binary is built from source with patches applied for serverless compatibility. See [`patches/`](patches/) for details.

Current patches:
- **etag-cache-control** - Disables caching on discovery endpoints to fix `kubectl` errors in serverless environments

## Versions

| Component | Version |
|-----------|---------|
| Kubernetes | 1.34.0 |
| etcd | 3.6.6 |

## Building

```bash
docker build -t kubernetes .
```

To build a specific version:

```bash
docker build --build-arg KUBE_VERSION=1.35 --build-arg KUBE_VERSION_PATCH=0 -t kubernetes:1.35.0 .
```
