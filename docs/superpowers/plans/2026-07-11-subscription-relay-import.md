# Subscription Relay Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add subscription preview/import so external VLESS/Trojan nodes can become PPanel relay rules on an entry node.

**Architecture:** Backend fetches and parses subscription content into relay rule candidates, frontend previews and appends selected candidates into the existing relay rule editor, and ppanel-node consumes the new `target_allow_insecure` relay field when generating Xray outbound TLS config. Existing relay rule save and node delivery flows remain unchanged.

**Tech Stack:** Go backend, Go ppanel-node, React/Bun admin frontend, Xray outbound JSON.

---

## Files

- Backend:
  - Modify `backend/internal/model/system.go` or the existing node config model file that defines `NodeRelayRule`.
  - Add a focused subscription parser package under `backend/internal/logic/admin/server` or the nearest existing admin node-config logic package.
  - Modify admin routes and handlers for a preview endpoint following existing route style.
  - Add Go tests for parser behavior.
- Node:
  - Modify the node API/config type that defines relay rules.
  - Modify relay outbound generation to pass `TargetAllowInsecure` into `panel.Outbound.AllowInsecure`.
  - Add or extend relay outbound tests.
- Frontend:
  - Modify the existing relay rules input component.
  - Modify frontend relay rule types/schema to include `target_allow_insecure`.
  - Add API client method for subscription preview.
  - Add import dialog UI.

## Task 1: Backend Relay Field and Subscription Parser

- [ ] Write a failing Go test for parsing a Base64 VLESS XHTTP TLS subscription.

Create or update the parser test with a case equivalent to:

```go
func TestParseSubscriptionRelayRulesMapsVlessXhttpTLS(t *testing.T) {
	raw := base64.StdEncoding.EncodeToString([]byte("vless://11111111-1111-1111-1111-111111111111@hk1.example.com:443?type=xhttp&security=tls&sni=update.microsoft.com&path=%2Fpath&allowInsecure=1#HK%201"))
	rules, skipped := ParseSubscriptionRelayRules(raw, ImportOptions{ListenPortStart: 643, ListenPortStep: 100})
	require.Empty(t, skipped)
	require.Len(t, rules, 1)
	require.Equal(t, 643, rules[0].ListenPort)
	require.Equal(t, "vless", rules[0].TargetProtocol)
	require.Equal(t, "11111111-1111-1111-1111-111111111111", rules[0].TargetUUID)
	require.Equal(t, "hk1.example.com", rules[0].TargetAddress)
	require.Equal(t, 443, rules[0].TargetPort)
	require.Equal(t, "xhttp", rules[0].TargetTransport)
	require.Equal(t, "tls", rules[0].TargetSecurity)
	require.Equal(t, "update.microsoft.com", rules[0].TargetSNI)
	require.Equal(t, "/path", rules[0].TargetPath)
	require.True(t, rules[0].TargetAllowInsecure)
}
```

- [ ] Run the focused test and verify it fails because parser/types are missing.

Run:

```powershell
go test ./internal/logic/admin/server -run TestParseSubscriptionRelayRulesMapsVlessXhttpTLS -count=1
```

- [ ] Add `TargetAllowInsecure bool json:"target_allow_insecure"` to backend relay rule config structs.

- [ ] Implement the parser with these rules:
  - If content is Base64, decode it; otherwise parse as plain text.
  - Split by line.
  - Support `vless://` and `trojan://`.
  - Skip entries with empty host or host `0.0.0.0`.
  - Map query fields into relay target fields.
  - Generate listen ports from `ListenPortStart + index * ListenPortStep`.
  - Return skipped entries with a name and reason.

- [ ] Run parser tests and commit backend parser work.

Commit:

```powershell
git -C backend add .
git -C backend commit -m "feat: parse relay subscription nodes"
```

## Task 2: Backend Preview Endpoint

- [ ] Write a failing handler/logic test that previews a subscription URL from an `httptest.Server`.

The test should return a Base64 body with one VLESS link and assert the response includes one rule and no skipped rows.

- [ ] Implement a preview request/response type:

```go
type SubscriptionRelayPreviewReq struct {
	URL             string `json:"url"`
	ListenPortStart int   `json:"listen_port_start"`
	ListenPortStep  int   `json:"listen_port_step"`
}

type SubscriptionRelayPreviewResp struct {
	Rules   []NodeRelayRule              `json:"rules"`
	Skipped []SubscriptionRelaySkipEntry `json:"skipped"`
}
```

- [ ] Add the admin route using existing middleware/auth patterns.

- [ ] Use an HTTP client with timeout and max body size.

- [ ] Run focused backend tests and commit.

Commit:

```powershell
git -C backend add .
git -C backend commit -m "feat: preview relay subscription imports"
```

## Task 3: Node `target_allow_insecure` Delivery

- [ ] Write a failing node test for relay outbound TLS `AllowInsecure`.

Use a relay rule with:

```go
TargetSecurity: "tls",
TargetSNI: "update.microsoft.com",
TargetAllowInsecure: true,
```

Assert the generated outbound stream TLS setting has `AllowInsecure == true`.

- [ ] Add `TargetAllowInsecure bool json:"target_allow_insecure"` to the node relay rule type.

- [ ] Pass it into the generated `panel.Outbound`.

- [ ] Run node tests and commit.

Run:

```powershell
$env:GOEXPERIMENT='jsonv2'; go test ./core/relay ./core/outbound ./core ./node -count=1 -timeout 60s
```

Commit:

```powershell
git -C node add .
git -C node commit -m "feat: honor relay tls allow insecure"
```

## Task 4: Frontend Import UI

- [ ] Add `target_allow_insecure` to relay rule TypeScript schema/defaults.

- [ ] Add an API method for the backend preview endpoint.

- [ ] Add `从订阅导入` button and dialog to the existing relay rules component.

- [ ] Dialog behavior:
  - URL input.
  - start listen port input, default `643`.
  - listen port step input, default `100`.
  - preview button calls backend.
  - preview table supports selecting rows.
  - import button appends selected rows to the existing rules array.
  - skipped rows display reason text.

- [ ] Add `允许不安全 TLS` in advanced target options.

- [ ] Run frontend type/build verification and commit.

Commit:

```powershell
git -C front add .
git -C front commit -m "feat: import relay rules from subscription"
```

## Task 5: End-to-End Docker Verification

- [ ] Rebuild local Docker services.

Run:

```powershell
docker compose -f docker-local\docker-compose.yml build ppanel admin-web
```

- [ ] Start or restart local services.

Run:

```powershell
docker compose -f docker-local\docker-compose.yml up -d
```

- [ ] Verify backend health and admin web load.

Run:

```powershell
Invoke-WebRequest -UseBasicParsing http://localhost:18080
Invoke-WebRequest -UseBasicParsing http://localhost:13001
```

- [ ] Verify the preview endpoint with a local test subscription body or the provided subscription URL, masking credentials in any user-facing output.

- [ ] Commit root docker/doc verification updates only if files changed.

