# Kubernetes Stack Bundle

Lightweight bundle of the binaries needed to stand up a minimal Kubernetes control plane. Instead of shipping a full etcd, the repo provides an embedded etcd binary to keep local and CI usage small and fast.

## What’s Included

- `/kubernetes/etcd` (a lightweight tmpfs-bound etcd)
- `/kubernetes/etcdctl`
- `/kubernetes/kube-apiserver`
- `/kubernetes/kube-controller-manager`
- `/kubernetes/kube-scheduler`
- `/kubernetes/kubectl`
- `/kubernetes/dashboard-auth`
- `/kubernetes/dashboard-api`
- `/kubernetes/dashboard-web` (and related files)
