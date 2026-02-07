# Patches

## 01-etag-cache-control.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Changes:**
- Sets `Cache-Control` header from `public` to `no-cache, private`
- Removes `If-None-Match` / 304 Not Modified logic

**Why:** The aggregated discovery endpoints (`/api`, `/apis`) return `Cache-Control: public` by default, allowing intermediate caches (CDNs, proxies) to store responses. In serverless scenarios (e.g., Lambda), this causes stale discovery data to be served when the API server cold starts or scales dynamically. The symptom is `kubectl` errors like `"the server doesn't have a resource type 'namespaces'"` even though the resource exists.

Using `no-cache, private` ensures clients always revalidate with the origin server and prevents shared caches from storing the response. The `If-None-Match` / 304 logic is also removed to guarantee full responses are always returned, avoiding edge cases where cached ETags from a previous server instance cause incorrect cache hits.

**File:** `staging/src/k8s.io/apiserver/pkg/endpoints/discovery/aggregated/etag.go`

## 01-shared-etcd-client.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Changes:**
- Adds reference-counted etcd client sharing across storage backends
- Multiple storage backends with the same transport config share a single client
- Reduces TCP connections from ~164 (one per resource type) to 1 per unique transport

**Why:** The kube-apiserver creates a separate etcd client for each storage backend (~164 for built-in resource types, more with CRDs). During startup, all these clients attempt to connect simultaneously, causing a "thundering herd" problem. This manifests as:

- ~60 connection failures with errors like `"operation was canceled"` or `"use of closed network connection"`
- 100 retry warning messages per failed connection (hardcoded in etcd client)
- ~2-3 second startup delay while connections retry and stabilize

In serverless environments (e.g., Lambda), this startup overhead is significant for cold starts.

This patch implements client sharing using the same reference-counting pattern as the existing compactor caching. Storage backends with identical transport configurations (same etcd servers, TLS settings) now share a single underlying connection.

**Impact:**
- Reduces etcd connections from ~164 to 1 (or few, if using etcd-servers-overrides)
- Eliminates connection failure warnings during startup
- Reduces cold start latency by ~2-3 seconds
- Reduces memory usage (each etcd client has overhead)

**Related:** https://github.com/kubernetes/kubernetes/issues/111622

**File:** `staging/src/k8s.io/apiserver/pkg/storage/storagebackend/factory/etcd3.go`

## 01-kubelet-external-dns.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Changes:**
- Adds `KUBELET_EXTERNAL_DNS` environment variable to register an `ExternalDNS` address in `node.Status.Addresses`
- Adds `KUBELET_EXTERNAL_PORT` environment variable to override the port in `node.Status.DaemonEndpoints.KubeletEndpoint.Port`

**Why:** In serverless/hybrid environments, the API server and kubelets may be on different networks. Features like `kubectl logs` and `kubectl exec` require the API server to connect back to the kubelet. When the kubelet is behind a tunnel (e.g., cloudflared), it needs to advertise a reachable hostname and port.

Kubernetes provides `ExternalDNS` as an address type for this purpose, but only cloud providers can set it. The kubelet also reports its listening port, but there's no way to advertise a different port (e.g., tunnel port 443 vs actual listening port). This patch allows operators to decouple the advertised address and port from the actual listening configuration.

**Usage:**
```bash
# On kubelet (node)
export KUBELET_EXTERNAL_DNS="my-node.trycloudflare.com"
export KUBELET_EXTERNAL_PORT="443"

# On API server
kube-apiserver --kubelet-preferred-address-types=ExternalDNS
```

**File:** `pkg/kubelet/nodestatus/setters.go`

## 02-watch-env.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Depends on:** `00-cnuss-kubernetes` (remote patch)

**Changes:**
- Adds environment variable configuration for watch/backoff parameters in the client-go reflector

**Why:** The remote patch (`cnuss:issues/136823`) refactors the reflector's backoff mechanism to use configurable defaults. This patch exposes those defaults via environment variables, allowing operators to tune watch behavior without code changes.

**Environment Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `WATCH_MIN_TIMEOUT` | `5m` | Minimum watch request timeout |
| `WATCH_MAX_TIMEOUT` | `10m` | Maximum watch request timeout (random in [min, max]) |
| `WATCH_BACKOFF_INIT` | `800ms` | Initial backoff duration on failure |
| `WATCH_BACKOFF_MAX` | `30s` | Maximum backoff cap |
| `WATCH_BACKOFF_RESET` | `2m` | Duration without backoff before resetting to initial |
| `WATCH_BACKOFF_FACTOR` | `2.0` | Exponential backoff multiplier |
| `WATCH_BACKOFF_JITTER` | `1.0` | Jitter factor for backoff randomization |

**Usage:**
```bash
# Reduce backoff for faster recovery in controlled environments
export WATCH_BACKOFF_INIT="100ms"
export WATCH_BACKOFF_MAX="5s"

# Increase watch timeout for slow networks
export WATCH_MIN_TIMEOUT="10m"
export WATCH_MAX_TIMEOUT="20m"
```

**File:** `staging/src/k8s.io/client-go/tools/cache/reflector.go`

## 03-empty-backoff.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Depends on:** `00-cnuss-kubernetes` (remote patch), `02-watch-env.patch`

**Changes:**
- Adds optional backoff when a watch closes with zero events received
- Controlled by `WATCH_BACKOFF_ON_EMPTY` environment variable (default: `false`)

**Why:** In some scenarios, empty watches (watches that close without receiving any events) can indicate an issue worth backing off on. For example, rapid reconnection loops on idle resources can create unnecessary load. However, this is disabled by default because empty watches are normal for idle resources - a watch on a namespace with no activity will naturally close and reconnect without receiving events.

**Environment Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `WATCH_BACKOFF_ON_EMPTY` | `false` | Enable backoff when watch closes with no events |

**Usage:**
```bash
# Enable backoff on empty watches (use with caution)
export WATCH_BACKOFF_ON_EMPTY="true"
```

**File:** `staging/src/k8s.io/client-go/tools/cache/reflector.go`
