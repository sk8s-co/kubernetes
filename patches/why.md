# Patches

## etag-cache-control.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Changes:**
- Sets `Cache-Control` header from `public` to `no-cache, private`
- Removes `If-None-Match` / 304 Not Modified logic

**Why:** The aggregated discovery endpoints (`/api`, `/apis`) return `Cache-Control: public` by default, allowing intermediate caches (CDNs, proxies) to store responses. In serverless scenarios (e.g., Lambda), this causes stale discovery data to be served when the API server cold starts or scales dynamically. The symptom is `kubectl` errors like `"the server doesn't have a resource type 'namespaces'"` even though the resource exists.

Using `no-cache, private` ensures clients always revalidate with the origin server and prevents shared caches from storing the response. The `If-None-Match` / 304 logic is also removed to guarantee full responses are always returned, avoiding edge cases where cached ETags from a previous server instance cause incorrect cache hits.

**File:** `staging/src/k8s.io/apiserver/pkg/endpoints/discovery/aggregated/etag.go`

## disable-apiserver-identity.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Changes:**
- Disables `APIServerIdentity` feature gate by default (Beta → default false)

**Why:** The APIServerIdentity feature creates Lease objects in `kube-system` for each API server instance, storing private IP addresses for peer discovery and proxy functionality. In serverless environments (e.g., Lambda), API server instances don't have stable private IPs that peers can reach - they're behind load balancers or NAT. The peer proxy feature assumes direct IP connectivity between API servers, which doesn't exist in serverless architectures.

Disabling this feature avoids the broken peer discovery mechanism entirely.

**Files:**
- `staging/src/k8s.io/apiserver/pkg/features/kube_features.go`
- `pkg/features/kube_features.go`

## watch.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Changes:**
- Server-side (get.go): `REQUEST_MIN_TIMEOUT`, `REQUEST_MAX_TIMEOUT` enforce timeout bounds on all watch requests (clamps client-specified timeouts)
- Client-side (reflector.go): `WATCH_MIN_TIMEOUT`, `WATCH_MAX_TIMEOUT` control outgoing watch timeout range `[min, max]`
- Client-side: `WATCH_BACKOFF_INIT`, `WATCH_BACKOFF_MAX`, `WATCH_BACKOFF_RESET` (seconds)
- Client-side: `WATCH_BACKOFF_FACTOR`, `WATCH_BACKOFF_JITTER` (floats)
- Client-side: `WATCH_BACKOFF_ON_EMPTY` (bool) - trigger backoff when watch closes with no events
- V(2) logging for watch open/close

**Why:** In serverless environments, long-lived HTTP connections and aggressive reconnection are problematic. This patch allows operators to tune watch behavior via environment variables without code changes.

The server-side `REQUEST_MIN_TIMEOUT` / `REQUEST_MAX_TIMEOUT` enforce limits regardless of what clients (like k9s, kubectl, etc.) request. This ensures external clients can't hold connections open longer than the server allows.

The client-side `WATCH_BACKOFF_ON_EMPTY` option addresses a specific serverless issue: when watches return no events (common for idle resources), the default behavior is to immediately reconnect. With short watch timeouts, this causes rapid polling. Enabling this option treats empty watches like a 429 response - backing off before reconnecting.

**Server-side defaults:**
- `REQUEST_MIN_TIMEOUT`: 0 (disabled - no minimum enforcement)
- `REQUEST_MAX_TIMEOUT`: 0 (disabled - no maximum enforcement)

**Client-side defaults (original Kubernetes behavior):**
- `WATCH_MIN_TIMEOUT`: 300 (5 minutes)
- `WATCH_MAX_TIMEOUT`: 600 (10 minutes)
- `WATCH_BACKOFF_INIT`: 0.8 seconds (800ms - use 1 for 1 second minimum)
- `WATCH_BACKOFF_MAX`: 30 seconds
- `WATCH_BACKOFF_RESET`: 120 seconds (2 minutes)
- `WATCH_BACKOFF_FACTOR`: 2.0
- `WATCH_BACKOFF_JITTER`: 1.0
- `WATCH_BACKOFF_ON_EMPTY`: false (disabled)

**Example (server enforces max 60s watches):**
```bash
# On API server
REQUEST_MAX_TIMEOUT=60            # cap all watches at 60 seconds
```

**Example (client short watches with backoff on empty):**
```bash
# On kubelet/controllers
WATCH_MIN_TIMEOUT=2               # 2 second watches
WATCH_MAX_TIMEOUT=4               # 4 second watches
WATCH_BACKOFF_INIT=1              # start at 1 second between watches
WATCH_BACKOFF_MAX=30              # grow to 30 seconds when idle
WATCH_BACKOFF_ON_EMPTY=true       # backoff when no events received
```

**Files:**
- `staging/src/k8s.io/apiserver/pkg/endpoints/handlers/get.go`
- `staging/src/k8s.io/client-go/tools/cache/reflector.go`

## shared-etcd-client.patch

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

## kubelet-external-dns.patch

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

## exec.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Changes:**
- Sets `upgradeRequired` to `false` for pod exec requests
- Sets `UseLocationHost` to `true` for all proxy handlers

**Why:** In the default Kubernetes flow, the API server proxies exec requests to the kubelet and requires an HTTP upgrade (SPDY/WebSocket). This fails in serverless environments where the API server can't maintain long-lived upgraded connections.

By setting `upgradeRequired=false`, the API server allows the request to be handled as a normal proxy request, enabling alternative patterns like redirecting the client directly to the kubelet's public endpoint (via cloudflared tunnel). This lets the kubelet handle the exec upgrade directly with the client.

`UseLocationHost=true` ensures the HTTP Host header sent to the kubelet matches the kubelet's address (e.g., `my-node.trycloudflare.com`) rather than the API server's address (e.g., `lambda-url.amazonaws.com`). Without this, cloudflared tunnels reject the request with a 403 due to Host header mismatch.

**Flow (before):**
```
kubectl exec → API server → [UPGRADE REQUIRED] → fails in Lambda
```

**Flow (after):**
```
kubectl exec → API server → proxy/redirect → kubelet (handles upgrade directly)
```

**TODO:** Make these changes conditional — only apply when the target kubelet's address type is `ExternalDNS`. This would preserve normal behavior for internal kubelets while enabling redirect for tunneled nodes.

**File:** `pkg/registry/core/pod/rest/subresources.go`
