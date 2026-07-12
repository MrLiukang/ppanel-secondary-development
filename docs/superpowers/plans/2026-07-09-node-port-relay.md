# Node Port Relay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 3x-ui-like relay capability to PPanel so one server node can listen on multiple inbound ports and route each inbound port to a configured target server.

**Architecture:** Keep existing `routing_rules` for Xray route matching, and add a focused `relay_rules` config layer that describes `listen port -> target outbound`. Backend validates and stores relay rules with the existing node config override model, node expands relay rules into Xray inbound + outbound + routing objects, and the admin UI exposes the rules under `Xray 设置` in maintenance.

**Tech Stack:** Go backend, Go ppanel-node, React/Bun admin frontend, Xray inbound/outbound/routing JSON.

---

## Product Scheme

This feature implements the operator workflow:

```text
node1:643  -> hknode:6443
node1:8443 -> jpnode:443
node1:9443 -> sgnode:443
```

The UI should call this `中转规则` or `端口中转`, not a generic routing rule. Each rule creates one extra inbound on the current node, one outbound pointing at the target server, and one routing rule that binds `inboundTag` to `outboundTag`.

For example:

```json
{
  "id": "relay-hk",
  "enabled": true,
  "remark": "香港中转",
  "listen_port": 643,
  "network": "tcp,udp",
  "target_address": "hknode.example.com",
  "target_port": 6443,
  "target_protocol": "vless",
  "target_security": "tls",
  "target_transport": "tcp"
}
```

Node expands it into:

```json
{
  "inboundTag": "relay-in-relay-hk-643",
  "outboundTag": "relay-out-relay-hk-hknode-example-com-6443"
}
```

The existing advanced `routing_rules` editor remains available for 3x-ui-style manual rules. The relay UI is a higher-level helper that generates the Xray pieces needed for port-based forwarding.

## Scope

In scope:

- Global relay rules under `Xray 设置`.
- Per-server override/inherit behavior, matching the existing node config override UX.
- Node-side generation of extra Xray inbound handlers.
- Node-side generation of target outbounds.
- Node-side generation of routing rules that bind relay inbound tags to relay outbound tags.
- Validation for duplicate listen ports, invalid ports, missing targets, duplicate tags, and unsupported protocol/transport combinations.
- Tests for backend validation, node Xray generation, and frontend form output.

Out of scope for this pass:

- Live packet-level integration test across two real VPS nodes.
- Automatic discovery of remote node credentials from subscription nodes.
- Balancer management.
- 3x-ui route test tool.
- User-facing subscription changes.

## Data Model

Add `NodeRelayRule` to backend, node, and frontend API types:

```go
type NodeRelayRule struct {
	ID              string `json:"id"`
	Enabled         bool   `json:"enabled"`
	Sort            int64  `json:"sort"`
	Remark          string `json:"remark"`
	ListenPort      int    `json:"listen_port"`
	Network         string `json:"network"`
	TargetAddress   string `json:"target_address"`
	TargetPort      int    `json:"target_port"`
	TargetProtocol  string `json:"target_protocol"`
	TargetSecurity  string `json:"target_security"`
	TargetSNI       string `json:"target_sni"`
	TargetTransport string `json:"target_transport"`
	TargetHost      string `json:"target_host"`
	TargetPath      string `json:"target_path"`
	TargetUUID      string `json:"target_uuid"`
	TargetPassword  string `json:"target_password"`
}
```

Use conservative defaults:

- `network`: default `tcp,udp`.
- `target_protocol`: default `vless` only if UI has enough fields to build it.
- `target_transport`: default `tcp`.
- `target_security`: default `none`.

Generated tags:

```text
inboundTag  = relay-in-{rule_id}-{listen_port}
outboundTag = relay-out-{rule_id}-{target_address_slug}-{target_port}
```

Do not let admins manually edit generated tags in the first version. Tags must be deterministic so saved routing rules and runtime reloads remain stable.

## Backend Plan

### Task 1: Backend Type And Config Plumbing

**Files:**

- Modify: `backend/apis/types.api`
- Modify: `backend/internal/types/types.go`
- Modify: `backend/internal/config/config.go`
- Modify: `backend/internal/logic/nodeconfig/override.go`
- Test: `backend/internal/logic/nodeconfig/override_test.go`

- [ ] **Step 1: Add failing test for global relay rule normalization**

Add a test in `backend/internal/logic/nodeconfig/override_test.go`:

```go
func TestNormalizeRelayRules(t *testing.T) {
	rules := NormalizeRelayRules([]types.NodeRelayRule{{
		ID:              " hk ",
		Enabled:         true,
		Sort:            2,
		Remark:          " HK relay ",
		ListenPort:      643,
		Network:         " tcp,udp ",
		TargetAddress:   " hknode.example.com ",
		TargetPort:      6443,
		TargetProtocol:  " vless ",
		TargetSecurity:  " tls ",
		TargetSNI:       " hknode.example.com ",
		TargetTransport: " tcp ",
		TargetUUID:      " 11111111-1111-1111-1111-111111111111 ",
	}})
	if len(rules) != 1 {
		t.Fatalf("len = %d, want 1", len(rules))
	}
	got := rules[0]
	if got.ID != "hk" || got.Remark != "HK relay" || got.TargetAddress != "hknode.example.com" {
		t.Fatalf("normalized rule = %#v", got)
	}
}
```

- [ ] **Step 2: Add failing test for duplicate listen ports**

```go
func TestValidateRelayRulesRejectsDuplicateListenPort(t *testing.T) {
	err := ValidateRelayRules([]types.NodeRelayRule{
		{ID: "a", Enabled: true, ListenPort: 643, TargetAddress: "hk.example.com", TargetPort: 443, TargetProtocol: "vless"},
		{ID: "b", Enabled: true, ListenPort: 643, TargetAddress: "jp.example.com", TargetPort: 443, TargetProtocol: "vless"},
	})
	if err == nil {
		t.Fatal("ValidateRelayRules() error = nil, want duplicate listen port error")
	}
}
```

- [ ] **Step 3: Run test to prove failure**

Run in `backend`:

```bash
go test ./internal/logic/nodeconfig -run 'TestNormalizeRelayRules|TestValidateRelayRulesRejectsDuplicateListenPort' -count=1
```

Expected: compile failure because `NodeRelayRule`, `NormalizeRelayRules`, and `ValidateRelayRules` do not exist.

- [ ] **Step 4: Add `relay_rules` to API/config types**

Add `RelayRules []NodeRelayRule json:"relay_rules"` to:

- `types.NodeConfig`
- `types.ServerNodeConfigValues`
- `types.ServerNodeConfigOverride`
- `config.NodeConfig`

Add generated/API schema equivalent in `backend/apis/types.api`.

- [ ] **Step 5: Implement normalization and validation**

Create functions in `backend/internal/logic/nodeconfig/override.go`:

```go
func NormalizeRelayRules(values []types.NodeRelayRule) []types.NodeRelayRule
func ValidateRelayRules(rules []types.NodeRelayRule) error
```

Validation rules:

- Disabled rules can be saved but are not sent to node.
- Enabled rules require `listen_port` between 1 and 65535.
- Enabled rules require `target_address`.
- Enabled rules require `target_port` between 1 and 65535.
- Enabled rules require `target_protocol` in `vless`, `vmess`, `trojan`, `shadowsocks`, `socks`, `http`.
- `network` must be empty, `tcp`, `udp`, or `tcp,udp`.
- Enabled relay rules cannot reuse the same `listen_port`.

- [ ] **Step 6: Include relay rules in override paths**

Update:

- `GlobalValues`
- `ApplyOverride`
- `OverrideResponse`
- `OverrideModel`
- `CloneValues`

Use the same inherit/override pattern as routing rules. Do not introduce a separate database table in this phase; store JSON in the existing override JSON column pattern if available. If the existing table lacks a relay JSON column, add one migration named after the current migration sequence.

- [ ] **Step 7: Run backend focused tests**

```bash
go test ./internal/logic/nodeconfig -count=1
```

Expected: PASS.

- [ ] **Step 8: Commit backend feature point**

```bash
git -C backend add apis/types.api internal/types/types.go internal/config/config.go internal/logic/nodeconfig/override.go internal/logic/nodeconfig/override_test.go
git -C backend commit -m "feat: add relay rule config model"
```

### Task 2: Backend Node Config Delivery

**Files:**

- Modify: `backend/internal/logic/server/queryServerProtocolConfigLogic.go`
- Modify: `backend/internal/logic/admin/system/getNodeConfigLogic.go`
- Modify: `backend/internal/logic/admin/system/updateNodeConfigLogic.go`
- Modify: `backend/internal/logic/admin/server/getServerNodeConfigLogic.go`
- Modify: `backend/internal/logic/admin/server/updateServerNodeConfigLogic.go`
- Test: focused tests where existing node config tests live

- [ ] **Step 1: Add failing test for node-facing relay filtering**

```go
func TestNodeFacingRelayRulesSkipsDisabled(t *testing.T) {
	got := NodeFacingRelayRules([]types.NodeRelayRule{
		{ID: "off", Enabled: false, ListenPort: 1111, TargetAddress: "off.example.com", TargetPort: 443, TargetProtocol: "vless"},
		{ID: "on", Enabled: true, ListenPort: 643, TargetAddress: "hk.example.com", TargetPort: 6443, TargetProtocol: "vless"},
	})
	if len(got) != 1 || got[0].ID != "on" {
		t.Fatalf("NodeFacingRelayRules() = %#v", got)
	}
}
```

- [ ] **Step 2: Implement `NodeFacingRelayRules`**

Add:

```go
func NodeFacingRelayRules(rules []types.NodeRelayRule) []types.NodeRelayRule
```

This returns normalized enabled rules only.

- [ ] **Step 3: Add relay rules to effective node config response**

Where backend currently builds node-facing config with DNS, outbound, and routing rules, include:

```go
RelayRules: nodeconfig.NodeFacingRelayRules(values.RelayRules)
```

- [ ] **Step 4: Validate relay rules on update**

Both global `UpdateNodeConfig` and server override `UpdateServerNodeConfig` must call `ValidateRelayRules` before saving.

- [ ] **Step 5: Clear server config cache after update**

Verify the existing update path clears `node.ServerConfigCacheKey` for the affected server. If routing updates already do this, include relay updates in the same path.

- [ ] **Step 6: Run backend tests**

```bash
go test ./internal/logic/nodeconfig ./internal/logic/admin/server ./internal/logic/admin/system -count=1
```

Expected: PASS, or package list adjusted to existing testable packages if admin packages have no tests.

- [ ] **Step 7: Commit backend delivery**

```bash
git -C backend add internal/logic
git -C backend commit -m "feat: deliver relay rules to nodes"
```

## Node Plan

### Task 3: Node Relay Types And Expansion

**Files:**

- Modify: `node/api/panel/server.go`
- Create: `node/core/relay/build.go`
- Test: `node/core/relay/build_test.go`

- [ ] **Step 1: Add failing node relay expansion test**

Create `node/core/relay/build_test.go`:

```go
package relay

import (
	"testing"

	"github.com/perfect-panel/ppanel-node/api/panel"
)

func TestBuildRelayPlanCreatesTags(t *testing.T) {
	rules := []panel.RelayRule{{
		ID:             "hk",
		Enabled:        true,
		ListenPort:     643,
		Network:        "tcp,udp",
		TargetAddress:  "hknode.example.com",
		TargetPort:     6443,
		TargetProtocol: "vless",
		TargetUUID:     "11111111-1111-1111-1111-111111111111",
	}}
	plan, err := BuildPlan(rules)
	if err != nil {
		t.Fatalf("BuildPlan() error = %v", err)
	}
	if len(plan.Inbounds) != 1 || len(plan.Outbounds) != 1 || len(plan.RoutingRules) != 1 {
		t.Fatalf("plan = %#v", plan)
	}
	if plan.RoutingRules[0].InboundTags[0] != "relay-in-hk-643" {
		t.Fatalf("inbound tag = %#v", plan.RoutingRules[0].InboundTags)
	}
}
```

- [ ] **Step 2: Run test to prove failure**

Run in `node`:

```bash
go test ./core/relay -run TestBuildRelayPlanCreatesTags -count=1
```

Expected: package or symbol missing.

- [ ] **Step 3: Add `RelayRule` to panel API**

Add to `node/api/panel/server.go`:

```go
RelayRules *[]RelayRule `json:"relay_rules"`
```

Define `RelayRule` with the same JSON fields as backend `NodeRelayRule`.

- [ ] **Step 4: Implement relay plan builder**

`BuildPlan` returns:

```go
type Plan struct {
	Inbounds     []RelayInbound
	Outbounds    []panel.Outbound
	RoutingRules []panel.RoutingRule
}
```

Each enabled rule produces:

- one inbound descriptor with tag and listen port;
- one `panel.Outbound` with generated tag, target address, target port, target protocol, transport, security, UUID/password;
- one `panel.RoutingRule` with `InboundTags: []string{inboundTag}` and `OutboundTag: outboundTag`.

- [ ] **Step 5: Run relay tests**

```bash
go test ./core/relay -count=1
```

Expected: PASS.

- [ ] **Step 6: Commit node relay expansion**

```bash
git -C node add api/panel/server.go core/relay/build.go core/relay/build_test.go
git -C node commit -m "feat: expand relay rules"
```

### Task 4: Node Runtime Inbound/Outbound/Routing Integration

**Files:**

- Modify: `node/core/xray.go`
- Modify: `node/core/outbound/build.go`
- Modify: `node/node/node.go`
- Test: `node/core/outbound/build_test.go`
- Test: `node/node/node_test.go` if existing test setup supports it

- [ ] **Step 1: Add focused test for relay outbound and routing merge**

Add a test in `node/core/outbound/build_test.go` that builds server config with one relay rule and asserts the router contains the generated `inboundTag -> outboundTag` rule.

- [ ] **Step 2: Merge relay outbounds/routing before Xray build**

In `outbound.Build`, expand `serverconfig.Data.RelayRules` and append generated outbounds before custom routing rules. Append generated routing rules after default DNS/block rules and before manual routing rules.

- [ ] **Step 3: Add relay inbound controllers**

In `node/node/node.go`, create additional controllers or lightweight inbound add calls for each relay inbound. Prefer reusing `core.AddNode(tag, info)` by constructing a `panel.NodeInfo` from the source protocol template and replacing `Protocol.Port` with `listen_port`.

Rules:

- Relay inbound must not start a separate user polling loop.
- Relay inbound uses the same user list/auth behavior as the base protocol if the inbound protocol needs users.
- Generated tag must match routing rule `inboundTag`.

- [ ] **Step 4: Validate duplicate runtime ports**

Extend `node/core/validate.go` to check:

- relay `listen_port` does not duplicate any enabled base protocol port;
- relay `listen_port` does not duplicate another relay rule;
- relay target port is valid.

- [ ] **Step 5: Run node tests**

```bash
$env:GOEXPERIMENT='jsonv2'; go test ./core/outbound ./core/relay ./core -count=1
```

Expected: PASS.

- [ ] **Step 6: Commit node runtime support**

```bash
git -C node add core node api/panel/server.go
git -C node commit -m "feat: apply relay rules at runtime"
```

## Frontend Plan

### Task 5: Admin Relay Rule UI

**Files:**

- Modify: `front/apps/admin/src/sections/xray-settings/index.tsx`
- Create: `front/apps/admin/src/sections/xray-settings/relay-rules-input.tsx`
- Modify: `front/apps/admin/src/sections/servers/server-node-config.tsx`
- Modify: `front/packages/ui/src/services/admin/typings.d.ts`

- [ ] **Step 1: Extend frontend API typings**

Add to `API.NodeConfig`, `API.ServerNodeConfigValues`, and `API.ServerNodeConfigOverride`:

```ts
relay_rules: API.NodeRelayRule[];
```

Add:

```ts
type NodeRelayRule = {
  id: string;
  enabled: boolean;
  sort: number;
  remark: string;
  listen_port: number;
  network: string;
  target_address: string;
  target_port: number;
  target_protocol: string;
  target_security: string;
  target_sni: string;
  target_transport: string;
  target_host: string;
  target_path: string;
  target_uuid: string;
  target_password: string;
};
```

- [ ] **Step 2: Add zod schema**

Add relay rule validation to global and per-server node config forms:

```ts
const relayRuleSchema = z.object({
  id: z.string(),
  enabled: z.boolean(),
  sort: z.number(),
  remark: z.string(),
  listen_port: z.coerce.number().int().min(1).max(65535),
  network: z.string(),
  target_address: z.string().min(1),
  target_port: z.coerce.number().int().min(1).max(65535),
  target_protocol: z.string(),
  target_security: z.string(),
  target_sni: z.string(),
  target_transport: z.string(),
  target_host: z.string(),
  target_path: z.string(),
  target_uuid: z.string(),
  target_password: z.string(),
});
```

- [ ] **Step 3: Build `RelayRulesInput`**

UI requirements:

- Chinese labels.
- Table columns: 启用, 入口端口, 目标地址, 目标端口, 协议, 备注, 操作.
- Add/edit drawer or accordion matching existing PPanel component style.
- Common fields shown by default: 启用, 备注, 入口端口, 网络, 目标地址, 目标端口, 目标协议.
- Advanced mode shows: TLS/SNI, transport, host, path, UUID, password.
- Show generated tag preview read-only:
  - `relay-in-{id}-{listen_port}`
  - `relay-out-{id}-{target_address}-{target_port}`

- [ ] **Step 4: Wire into global Xray settings**

Add a new tab under `front/apps/admin/src/sections/xray-settings/index.tsx`:

```text
中转规则
```

This tab edits `relay_rules`.

- [ ] **Step 5: Wire into per-server override**

Add `relay_rules` to `front/apps/admin/src/sections/servers/server-node-config.tsx`, including inherit/override behavior matching routing rules.

- [ ] **Step 6: Run frontend build**

```bash
bun run build
```

If full checks fail from existing unrelated formatting, record the exact failure boundary and run the admin build in Docker the same way current verification does.

- [ ] **Step 7: Commit frontend UI**

```bash
git -C front add apps/admin/src/sections/xray-settings apps/admin/src/sections/servers/server-node-config.tsx packages/ui/src/services/admin/typings.d.ts
git -C front commit -m "feat: add relay rule ui"
```

## Docker And Manual Verification

### Task 6: Docker Smoke Test

**Files:**

- Modify only if necessary: `docker-local/docker-compose.yml`

- [ ] **Step 1: Restart backend and admin web**

```bash
docker compose -f docker-local/docker-compose.yml up -d --no-build --force-recreate ppanel admin-web
```

- [ ] **Step 2: Verify containers are healthy/up**

```bash
docker compose -f docker-local/docker-compose.yml ps
```

Expected:

- `ppanel-local-server` is `Up`.
- `ppanel-local-admin-web` is `Up`.
- MySQL and Redis are healthy.

- [ ] **Step 3: Verify frontend responds**

```bash
Invoke-WebRequest -Uri http://localhost:13001 -UseBasicParsing -TimeoutSec 10
```

Expected: HTTP 200.

- [ ] **Step 4: Verify backend responds**

```bash
Invoke-WebRequest -Uri http://localhost:18080 -UseBasicParsing -TimeoutSec 10
```

Expected: backend reachable. A 404 on `/` is acceptable because the server has no root route.

## Acceptance Criteria

The feature is acceptable only when all of these are true:

- Admin can create a rule equivalent to `node1:643 -> hknode:6443`.
- Saving global `relay_rules` persists after refresh.
- Saving per-server relay override persists after refresh.
- Backend rejects two enabled relay rules using the same `listen_port`.
- Backend rejects invalid ports and missing target address.
- Node receives `relay_rules` from the control panel.
- Node generates an extra inbound tag for the listen port.
- Node generates an outbound to the target address/port.
- Node generates a routing rule binding generated `inboundTag` to generated `outboundTag`.
- Existing manual `routing_rules` still work.
- Existing node protocols still start normally.
- Focused backend tests pass.
- Focused node tests pass with `GOEXPERIMENT=jsonv2`.
- Frontend admin build passes or any failure is proven unrelated with a narrower build passing.
- Docker local backend and admin frontend start after the change.

## Commit Plan

Commit after each feature point:

1. `backend`: `feat: add relay rule config model`
2. `backend`: `feat: deliver relay rules to nodes`
3. `node`: `feat: expand relay rules`
4. `node`: `feat: apply relay rules at runtime`
5. `front`: `feat: add relay rule ui`
6. optional root docs/docker commit only if requested

Do not commit `docker-local/cache/GeoLite2-City.mmdb`.

## Risks And Boundary Checks

- First broken boundary to verify during implementation: whether backend node config response can carry `relay_rules` to `ppanel-node`.
- Second boundary: whether node can add extra inbound handlers without creating duplicate user polling controllers.
- Third boundary: whether generated outbounds are usable by Xray for each target protocol.
- Fourth boundary: whether existing cached server config is invalidated after relay changes.
- Fifth boundary: whether the UI override model can carry relay rules without accidentally overwriting DNS/outbound/routing settings.

