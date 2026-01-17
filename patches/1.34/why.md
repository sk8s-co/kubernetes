# Patches for Kubernetes 1.34

## [etag-cache-control.patch](etag-cache-control.patch)

**Change:** Sets `Cache-Control` header from `public` to `no-cache, private`

**Why:** The discovery endpoint is uncacheable in serverless scenarios. The `public` cache directive allows intermediate caches (CDNs, proxies) to store responses, which causes stale discovery data to be served when the API server scales dynamically. Using `no-cache, private` ensures clients always revalidate with the origin server and prevents shared caches from storing the response.
