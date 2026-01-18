# Kubernetes Stack Bundle

Minimal bundle of Kubernetes control plane binaries, with patches for serverless environments.

## What's Included

- `etcd`
- `etcdctl`
- `kube-apiserver` (built from source with patches)
- `kube-controller-manager`
- `kube-scheduler`
- `kubectl`
- `kubelet` (built from source with patches)

## Patches

Binaries built from source have patches applied for serverless compatibility. See [`patches/why.md`](patches/why.md) for details.

## Build Matrix

CI builds multi-arch images for each Kubernetes version. The build matrix is defined in [`.github/_versions.yaml`](.github/_versions.yaml).

| Kubernetes | Architectures |
|------------|---------------|
| 1.34 | `linux/amd64`, `linux/arm64` |
| 1.35 | `linux/amd64`, `linux/arm64` |

Images are published to `ghcr.io/sk8s-co/kubernetes:<version>`.

## Building Locally

```bash
docker build -t kubernetes .
```

To build a specific version:

```bash
docker build --build-arg KUBE_VERSION=1.35 --build-arg KUBE_VERSION_PATCH=0 -t kubernetes:1.35.0 .
```
