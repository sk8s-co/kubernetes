# Patches

## etag-cache-control.patch

**Versions:** `^1.34` (>=1.34.0 <2.0.0)

**Changes:**
- Sets `Cache-Control` header from `public` to `no-cache, private`
- Removes `If-None-Match` / 304 Not Modified logic

**Why:** The aggregated discovery endpoints (`/api`, `/apis`) return `Cache-Control: public` by default, allowing intermediate caches (CDNs, proxies) to store responses. In serverless scenarios (e.g., Lambda), this causes stale discovery data to be served when the API server cold starts or scales dynamically. The symptom is `kubectl` errors like `"the server doesn't have a resource type 'namespaces'"` even though the resource exists.

Using `no-cache, private` ensures clients always revalidate with the origin server and prevents shared caches from storing the response. The `If-None-Match` / 304 logic is also removed to guarantee full responses are always returned, avoiding edge cases where cached ETags from a previous server instance cause incorrect cache hits.

**File:** `staging/src/k8s.io/apiserver/pkg/endpoints/discovery/aggregated/etag.go`

## serverless-lease-tuning.patch

**Versions:** `^1.34` (>=1.34.0 <2.0.0)

**Changes:**
- `IdentityLeaseGCPeriod`: 3600s → 5s
- `IdentityLeaseDurationSeconds`: 3600 → 30
- `LeaseCandidateGCPeriod`: 30min → 1min

**Why:** The default API server lease timing values are optimized for long-running instances. In serverless environments where API servers are ephemeral and may terminate without graceful shutdown, stale identity leases accumulate in the `kube-system` namespace. The 1-hour GC period means orphaned leases persist far too long.

Reducing these values ensures faster cleanup of stale leases when API server instances scale down or terminate unexpectedly.

**File:** `pkg/controlplane/apiserver/server.go`

## identity-prefix-env.patch

**Versions:** `^1.34` (>=1.34.0 <2.0.0)

**Changes:**
- Adds support for `IDENTITY_PREFIX` environment variable to prefix the API server identity

**Why:** In serverless or multi-tenant environments, it can be useful to distinguish API server instances by adding a custom prefix to their identity. This allows operators to set `IDENTITY_PREFIX` to identify which deployment, region, or tenant an API server belongs to. The prefix is prepended to the generated `apiserver-<hash>` identity, resulting in IDs like `myprefix-apiserver-<hash>`.

**File:** `staging/src/k8s.io/apiserver/pkg/server/config.go`

## short-watch-timeout.patch

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Changes:**
- `defaultMinWatchTimeout`: 5 minutes → 5 seconds (client-side)
- Initial backoff: 800ms → 30 seconds (client-side)
- Max backoff: 30 seconds → 120 seconds (client-side)
- Removes 30-minute override for Secrets/ConfigMaps watch manager (client-side)
- Caps all watch requests to 10 seconds max (server-side)

**Why:** Kubernetes watch requests use long-lived HTTP connections (5-10 minutes by default, 30-60 minutes for Secrets/ConfigMaps). In serverless environments like AWS Lambda, HTTP requests must complete quickly due to execution time limits and the ephemeral nature of function instances.

The client-side changes reduce watch timeouts for the kubelet and add a 30-second baseline backoff (sequence: 30s → 60s → 120s max). The server-side change caps all watch requests to 10 seconds, catching third-party clients (kubectl, k9s, Lens, etc.) that use unpatched client-go with default 5-10 minute timeouts.

**Files:**
- `staging/src/k8s.io/client-go/tools/cache/reflector.go`
- `pkg/kubelet/util/manager/watch_based_manager.go`
- `staging/src/k8s.io/apiserver/pkg/endpoints/handlers/get.go`