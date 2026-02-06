# Experiments

Patches that are work-in-progress or didn't work out. Kept for reference and future exploration.

---

## exec.patch

**Status:** On hold - redirect approach doesn't work with Cloudflare

**Versions:** `^1.35` (>=1.35.0 <2.0.0)

**Goal:** Enable `kubectl exec` in serverless environments where the API server (Lambda) cannot maintain long-lived upgraded connections.

**Approach:** API server returns 307 redirect to kubelet's external endpoint (cloudflared tunnel) instead of proxying.

### Changes Made

- `ExecREST.Connect` returns 307 redirect to kubelet URL instead of proxying
- Sets `UpgradeRequired=false` and `UseLocationHost=true` on all proxy handlers (pod, node, service)
- `IsUpgradeRequest()` also returns `true` if `X-Stream-Protocol-Version` header is present
- `UpgradeResponse()` injects SPDY upgrade headers when `X-Stream-Protocol-Version` is present but upgrade headers are missing
- `tryUpgrade()` converts request to proper WebSocket upgrade: sets method to GET, adds WebSocket headers (`Connection`, `Upgrade`, `Sec-WebSocket-Key`, `Sec-WebSocket-Version`), and forces `UseLocationHost=false`
- Kubelet accepts both param styles (`input`/`stdin`, `output`/`stdout`, `error`/`stderr`) via `strconv.ParseBool`

### What We Learned

**The HTTP/2 header stripping problem:** Cloudflare's edge terminates HTTP/2 and translates to HTTP/1.1 for origin servers. During this translation, hop-by-hop headers like `Connection: Upgrade` and `Upgrade: SPDY/3.1` are stripped. However, `X-Stream-Protocol-Version` headers survive because they're not hop-by-hop.

**The 101 response problem:** Cloudflare's HTTP/2 translation converts `101 Switching Protocols` responses to `200 OK` for SPDY upgrades. Cloudflare only does native WebSocket passthrough when the **request** looks like a proper WebSocket upgrade (GET method + upgrade headers).

**Why the redirect approach fails:**

1. `kubectl exec` → API server (Lambda) → 307 redirect to kubelet's cloudflared URL
2. kubectl first tries WebSocket (GET + `Sec-Websocket-Protocol`) → gets 307 → can't upgrade a redirect
3. kubectl falls back to SPDY (POST + `X-Stream-Protocol-Version`) → gets 307
4. kubectl follows redirect → sends POST to cloudflared
5. kubelet receives POST, responds with 101 + `Sec-Websocket-Accept`
6. **Cloudflare converts 101 → 200** because the incoming request was POST, not a proper WebSocket GET
7. kubectl gets 200 instead of 101 → fails with empty response

**Key insight:** The WebSocket conversion code we added to `upgradeaware.go` only runs when the API server **proxies** to kubelet. With the redirect approach, the API server just returns 307 and kubectl connects directly to cloudflared - none of the conversion code runs.

### Attempted Solutions

1. **Header injection on kubelet:** Inject `Connection: Upgrade` and `Upgrade: SPDY/3.1` headers when `X-Stream-Protocol-Version` is present. Doesn't help because Cloudflare still sees POST, not GET.

2. **WebSocket conversion in API server proxy:** Convert SPDY POST to WebSocket GET in `tryUpgrade()`. Works for proxy path but redirect bypasses this entirely.

3. **UseLocationHost=false:** Tried preserving original Host header instead of using kubelet's address. Didn't help with the core problem.

### Potential Future Approaches

1. **Kubelet-side protocol conversion:** When kubelet receives POST + SPDY headers via cloudflared, have it create an internal proxy (like `UpgradeAwareHandler`) to CRI. The kubelet would accept the weird POST request and internally do proper WebSocket to CRI. Challenge: response back to kubectl still goes through Cloudflare.

2. **Double redirect:** API server redirects to kubelet, kubelet returns 303 (which converts POST to GET) to a WebSocket endpoint. kubectl would then GET with WebSocket upgrade. Needs investigation.

3. **Custom kubectl plugin:** A kubectl plugin that understands the redirect and properly upgrades to WebSocket. Invasive but would work.

4. **Different tunnel technology:** Something other than Cloudflare that properly handles SPDY 101 responses.

### Files Modified

- `pkg/registry/core/pod/rest/subresources.go` - ExecREST returns 307 redirect
- `pkg/registry/core/node/rest/proxy.go` - UpgradeRequired=false, UseLocationHost=true
- `pkg/registry/core/service/proxy.go` - UpgradeRequired=false, UseLocationHost=true
- `staging/src/k8s.io/apimachinery/pkg/util/httpstream/httpstream.go` - IsUpgradeRequest() accepts X-Stream-Protocol-Version
- `staging/src/k8s.io/apimachinery/pkg/util/httpstream/spdy/upgrade.go` - UpgradeResponse() injects upgrade headers
- `staging/src/k8s.io/apimachinery/pkg/util/proxy/upgradeaware.go` - tryUpgrade() converts to WebSocket (GET + headers + UseLocationHost=false)
- `staging/src/k8s.io/apiserver/pkg/util/proxy/streamtunnel.go` - Backend response validation accepts X-Stream-Protocol-Version
- `staging/src/k8s.io/kubelet/pkg/cri/streaming/remotecommand/httpstream.go` - Accepts both param styles

### Requirements (if it worked)

- Kubelet accessible via external endpoint (e.g., cloudflared tunnel)
- `--kubelet-preferred-address-types=ExternalDNS` on API server
- `KUBELET_EXTERNAL_DNS` and `KUBELET_EXTERNAL_PORT` set on kubelet (see `kubelet-external-dns.patch`)
