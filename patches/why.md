# Patches

## 01-apiserver-timeouts.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Changes:**
- Adds server-side watch request timeout clamping via environment variables
- `REQUEST_MIN_TIMEOUT` sets minimum timeout (in seconds)
- `REQUEST_MAX_TIMEOUT` sets maximum timeout (in seconds)

**Why:** In serverless environments, clients may request very short or very long watch timeouts that aren't optimal. This patch allows operators to enforce min/max bounds on watch request timeouts at the API server level, independent of what clients request.

**Environment Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `REQUEST_MIN_TIMEOUT` | `0` (disabled) | Minimum watch timeout in seconds |
| `REQUEST_MAX_TIMEOUT` | `0` (disabled) | Maximum watch timeout in seconds |

**Usage:**
```bash
# Enforce 30s minimum, 5 minute maximum watch timeouts
export REQUEST_MIN_TIMEOUT=30
export REQUEST_MAX_TIMEOUT=300
```

**File:** `staging/src/k8s.io/apiserver/pkg/endpoints/handlers/get.go`

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

## 01-kubelet-csi-disabled.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Changes:**
- Comments out the CSI volume plugin import and registration
- Comments out the CSIDriver informer startup

**Why:** In serverless environments that don't use CSI volumes (only emptyDir, configMap, secret, hostPath, projected), the CSI subsystem:
- Creates unnecessary watch connections (CSIDriver informer)
- Attempts CSINode initialization which fails if the node doesn't exist yet
- Adds startup latency waiting for CSI initialization

This patch completely disables CSI:
1. The CSI plugin is never loaded (no CSINode init errors)
2. The CSIDriver informer is never started (no watch connection)

**Impact:**
- ✅ emptyDir, hostPath, configMap, secret, projected, nfs, iscsi, fc volumes work normally
- ❌ CSI volumes will not be available

**Use this patch only if you don't need CSI volume support.**

**Files:**
- `cmd/kubelet/app/plugins.go`
- `pkg/kubelet/volumemanager/volume_manager.go`

## 01-kubelet-runtimeclass-disabled.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Changes:**
- Disables the RuntimeClass informer by commenting out `runtimeClassManager` initialization

**Why:** In serverless environments where only the default container runtime is used, the RuntimeClass informer creates unnecessary watch connections to the API server. Disabling it saves one informer/watch.

**Safety:** All usages of `runtimeClassManager` in kubelet have nil checks:
- `kuberuntime_sandbox.go:57`: `if m.runtimeClassManager != nil`
- `kubelet_pods.go:2792`: `if kl.runtimeClassManager == nil { return false }`
- `util/util.go:113`: `if pod != nil && rcManager != nil`

The only unsafe code path (`kuberuntime_container.go:182`) is behind the `RuntimeClassInImageCriAPI` feature gate, which is Alpha and disabled by default.

**Impact:**
- Pods **without** `spec.runtimeClassName`: Work normally with default runtime
- Pods **with** `spec.runtimeClassName`: Will fail (use this patch only if you don't use RuntimeClass)
- Saves one informer watch connection to API server

**File:** `pkg/kubelet/kubelet.go`

## 01-kubelet-sync-frequency.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Changes:**
- Uses `KubeletConfiguration.SyncFrequency` for Pod, Node, and Service reflector/informer resync periods instead of hardcoded `0`

**Why:** By default, kubelet creates reflectors/informers with `resyncPeriod = 0` (never resync). This means they rely solely on watch events and only re-list on watch reconnection. While this reduces API server load, it also means there's no periodic consistency check.

This patch uses the existing `SyncFrequency` config option (default: 1 minute) as the resync period, allowing operators to tune this behavior. Setting a longer `SyncFrequency` reduces API calls, while the default provides periodic consistency checks.

**Configuration:**
```yaml
# kubelet-config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
syncFrequency: 5m  # Pod/Node/Service reflectors resync every 5 minutes
```

**Affected Reflectors/Informers:**
| Reflector | Location | Before | After |
|-----------|----------|--------|-------|
| Pod | `config/apiserver.go:66` | `0` (never) | `SyncFrequency` |
| Node | `kubelet.go:473` | `0` (never) | `SyncFrequency` |
| Service | `kubelet.go:539` | `0` (never) | `SyncFrequency` |

**Files:**
- `pkg/kubelet/kubelet.go`
- `pkg/kubelet/config/apiserver.go`

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
