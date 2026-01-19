# Patches

## etag-cache-control.patch

**Versions:** 1.34, 1.35

**Changes:**
- Sets `Cache-Control` header from `public` to `no-cache, private`
- Removes `If-None-Match` / 304 Not Modified logic

**Why:** The aggregated discovery endpoints (`/api`, `/apis`) return `Cache-Control: public` by default, allowing intermediate caches (CDNs, proxies) to store responses. In serverless scenarios (e.g., Lambda), this causes stale discovery data to be served when the API server cold starts or scales dynamically. The symptom is `kubectl` errors like `"the server doesn't have a resource type 'namespaces'"` even though the resource exists.

Using `no-cache, private` ensures clients always revalidate with the origin server and prevents shared caches from storing the response. The `If-None-Match` / 304 logic is also removed to guarantee full responses are always returned, avoiding edge cases where cached ETags from a previous server instance cause incorrect cache hits.

**File:** `staging/src/k8s.io/apiserver/pkg/endpoints/discovery/aggregated/etag.go`

## disable-automount-serviceaccount-token.patch

**Versions:** 1.34, 1.35

**Changes:**
- Changes `shouldAutomount()` to return `false` by default instead of `true`

**Why:** Serverless Kubernetes deployments don't currently support service account token automounting. The projected volume for `kube-api-access-*` requires the `kube-root-ca.crt` ConfigMap, which doesn't exist in our minimal control plane setup. When automounting is enabled by default, pods fail with:

```
MountVolume.SetUp failed for volume "kube-api-access-n52z2" ... configmap "kube-root-ca.crt" not found
```

By defaulting to `false`, pods deploy successfully without requiring users to explicitly set `automountServiceAccountToken: false` on every pod or service account.

**File:** `plugin/pkg/admission/serviceaccount/admission.go`
