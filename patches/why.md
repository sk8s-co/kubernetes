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
- Adds environment variables for watch timeout and backoff configuration
- Server-side: `WATCH_MAX_TIMEOUT` caps incoming watch requests
- Client-side: `WATCH_MIN_TIMEOUT`, `WATCH_MAX_TIMEOUT` control timeout range `[min, max]`
- Client-side: `WATCH_BACKOFF_INIT`, `WATCH_BACKOFF_MAX`, `WATCH_BACKOFF_RESET` (seconds)
- Client-side: `WATCH_BACKOFF_FACTOR`, `WATCH_BACKOFF_JITTER` (floats)
- Client-side: `WATCH_BACKOFF_RESET_THRESHOLD` (int) - number of successful watches before backoff resets
- Activity-based backoff reset (opt-in): when `WATCH_BACKOFF_RESET_THRESHOLD` > 0, backoff resets after N successful watches

**Why:** In serverless environments, long-lived HTTP connections and aggressive reconnection are problematic. This patch allows operators to tune watch behavior via environment variables without code changes.

The activity-based reset (opt-in via `WATCH_BACKOFF_RESET_THRESHOLD`) enables adaptive polling: fast reconnects when there's activity (events being received), slower polling when idle. This is useful for short-lived watches where the original time-based reset (2 minutes) would never trigger.

**Defaults (original Kubernetes behavior):**
- `WATCH_MIN_TIMEOUT`: 300 (5 minutes)
- `WATCH_MAX_TIMEOUT`: 600 (10 minutes)
- `WATCH_BACKOFF_INIT`: 0.8 seconds (800ms - use 1 for 1 second minimum)
- `WATCH_BACKOFF_MAX`: 30 seconds
- `WATCH_BACKOFF_RESET`: 120 seconds (2 minutes)
- `WATCH_BACKOFF_FACTOR`: 2.0
- `WATCH_BACKOFF_JITTER`: 1.0
- `WATCH_BACKOFF_RESET_THRESHOLD`: 0 (disabled - use time-based reset only; set to 1+ to enable activity-based reset)

**Example (short watches with adaptive backoff):**
```bash
WATCH_MIN_TIMEOUT=2               # 2 second watches
WATCH_MAX_TIMEOUT=2
WATCH_BACKOFF_INIT=1              # start at 1 second between watches
WATCH_BACKOFF_MAX=60              # grow to 60 seconds when idle
WATCH_BACKOFF_RESET_THRESHOLD=1   # reset backoff after 1 successful watch
```
With these settings: fast polling when events are received, backs off to 60s gaps when no activity.

**Files:**
- `staging/src/k8s.io/apiserver/pkg/endpoints/handlers/get.go`
- `staging/src/k8s.io/client-go/tools/cache/reflector.go`
