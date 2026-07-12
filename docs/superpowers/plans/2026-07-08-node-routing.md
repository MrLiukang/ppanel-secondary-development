# Node Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Do not stage, commit, push, or open PRs unless the user explicitly asks.

**Goal:** Add a 3x-ui-style `Xray Settings` module under PPanel's existing Maintenance menu, including global rules, per-server append/override rules, backend APIs, node runtime conversion, frontend UI, and tests.

**Architecture:** Keep PPanel's existing node pull endpoint and server-specific `Node Config` override surface. Add a first-class structured `routing_rules` model beside existing `outbound`, `dns`, and `block` config. Backend normalizes and merges global/server rules; node converts effective rules to Xray `routing.rules`; frontend adds a new `/dashboard/xray-settings` page under Maintenance and keeps per-server overrides in the existing server `Node Config`.

**Tech Stack:** Go backend, Go node service, Xray-core router config, Bun/Turborepo, Vite, React 19, react-hook-form, zod, Vitest.

---

## File Structure

Backend:

- Modify `backend/apis/types.api`: add `NodeRoutingRule`, `RoutingMode`, and routing fields to node config types.
- Modify `backend/apis/admin/system.api`: keep existing endpoints; generated types include new fields.
- Modify `backend/apis/admin/server.api`: extend server node override request/response.
- Modify `backend/internal/types/types.go`: generated or manually updated API structs.
- Modify `backend/internal/config/config.go`: add `RoutingRules` to `NodeConfig` and `NodeDBConfig`.
- Modify `backend/internal/logic/admin/system/getNodeConfigLogic.go`: read global routing rules.
- Modify `backend/internal/logic/admin/system/updateNodeConfigLogic.go`: validate and save global routing rules.
- Modify `backend/internal/logic/admin/system/update_config.go`: include `RoutingRules` in config serialization.
- Modify `backend/internal/logic/nodeconfig/override.go`: normalize, validate, clone, merge, and serialize routing rules.
- Modify `backend/internal/logic/nodeconfig/override_test.go`: TDD tests for normalization and merge modes.
- Modify `backend/internal/model/node/server_config_override.go`: add routing override fields if the table model is column-backed.
- Modify migrations under `backend/initialize/migrate/database/mysql` and `backend/initialize/migrate/database/postgres` only if `server_config_overrides` needs new columns.
- Modify `backend/internal/logic/admin/server/getServerNodeConfigLogic.go`: include global/override/effective routing rules.
- Modify `backend/internal/logic/admin/server/updateServerNodeConfigLogic.go`: validate and save server routing mode/rules.
- Modify `backend/internal/logic/server/queryServerProtocolConfigLogic.go`: include effective `routing_rules` in `/v2/server/{id}` response.

Node:

- Modify `node/api/panel/server.go`: add `RoutingRules` model to panel response.
- Modify `node/core/outbound/build.go`: build Xray router rules from structured `routing_rules`.
- Modify `node/core/outbound/build_test.go`: tests for inboundTag/outboundTag, sort, match fields, and legacy compatibility.
- Modify `node/core/custom_test.go`: integration-level config conversion checks if needed.

Frontend:

- Modify `front/packages/ui/src/services/admin/typings.d.ts`: add generated/manual API types.
- Modify `front/packages/ui/src/services/common/typings.d.ts` and `front/packages/ui/src/services/user/typings.d.ts` only if shared generated types require consistency.
- Modify `front/apps/admin/src/layout/navs.ts`: add `Xray Settings` under `Maintenance`.
- Create `front/apps/admin/src/routes/dashboard/xray-settings.lazy.tsx`: route for the new Maintenance page.
- Create `front/apps/admin/src/sections/xray-settings/index.tsx`: page shell for global Xray settings.
- Modify `front/apps/admin/src/sections/servers/outbound-config.ts`: rename semantics from name to tag where possible; add reserved tag validation helpers.
- Modify `front/apps/admin/src/sections/servers/outbound-config-input.tsx`: preserve existing outbound editing, clarify tag naming.
- Create `front/apps/admin/src/sections/servers/routing-rule-config.ts`: zod schema, normalization, tag helpers, inbound tag helpers.
- Create `front/apps/admin/src/sections/servers/routing-rule-input.tsx`: 3x-ui-like rule table/editor embedded in existing UI.
- Move or reuse logic from `front/apps/admin/src/sections/servers/server-config.tsx`: global Xray settings should live on the new Maintenance page, while the old card may link to it or remain for basic node communication settings.
- Modify `front/apps/admin/src/sections/servers/server-node-config.tsx`: add per-server routing mode and rules tab.
- Add frontend tests near the new component files, using existing Vitest setup if present.

Docs:

- Keep `docs/superpowers/specs/2026-07-08-node-routing-design.md` as the accepted design.
- Keep this implementation plan as the execution source.

---

## Task 1: Backend Routing Rule Types and Normalization

**Files:**

- Modify `backend/apis/types.api`
- Modify `backend/internal/types/types.go`
- Modify `backend/internal/config/config.go`
- Modify `backend/internal/logic/nodeconfig/override.go`
- Test `backend/internal/logic/nodeconfig/override_test.go`

- [ ] **Step 1: Write failing backend normalization tests**

Add tests for:

```go
func TestRoutingRuleNormalization(t *testing.T) {
	values := nodeconfig.NormalizeRoutingRules([]types.NodeRoutingRule{
		{
			ID:          " cn-direct ",
			Enabled:     true,
			Sort:        20,
			Remark:      " CN Direct ",
			InboundTags: []string{" vless ", "", "vless"},
			OutboundTag: " direct ",
			Domain:      []string{" geosite:cn ", "", "geosite:cn"},
			IP:          []string{" geoip:cn "},
			Network:     " tcp,udp ",
		},
	})
	if len(values) != 1 {
		t.Fatalf("rules len = %d, want 1", len(values))
	}
	got := values[0]
	if got.ID != "cn-direct" || got.Remark != "CN Direct" || got.OutboundTag != "direct" {
		t.Fatalf("rule fields not normalized: %#v", got)
	}
	if len(got.InboundTags) != 1 || got.InboundTags[0] != "vless" {
		t.Fatalf("inbound tags = %#v, want [vless]", got.InboundTags)
	}
	if len(got.Domain) != 1 || got.Domain[0] != "geosite:cn" {
		t.Fatalf("domain = %#v, want [geosite:cn]", got.Domain)
	}
}

func TestValidateRoutingRulesRejectsMissingMatcher(t *testing.T) {
	err := nodeconfig.ValidateRoutingRules(
		[]types.NodeRoutingRule{{Enabled: true, OutboundTag: "direct"}},
		[]types.NodeOutbound{},
	)
	if err == nil {
		t.Fatal("ValidateRoutingRules() error = nil, want missing matcher error")
	}
}
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
cd C:\Users\pao\Documents\ppanel二开\backend
go test ./internal/logic/nodeconfig
```

Expected: fail because `NodeRoutingRule`, `NormalizeRoutingRules`, and `ValidateRoutingRules` do not exist.

- [ ] **Step 3: Add routing types**

Add API/model fields:

```go
type NodeRoutingRule struct {
	ID          string   `json:"id"`
	Enabled     bool     `json:"enabled"`
	Sort        int64    `json:"sort"`
	Remark      string   `json:"remark"`
	InboundTags []string `json:"inbound_tags"`
	OutboundTag string   `json:"outbound_tag"`
	Domain      []string `json:"domain"`
	IP          []string `json:"ip"`
	Port        string   `json:"port"`
	Protocol    string   `json:"protocol"`
	Network     string   `json:"network"`
}
```

Add `RoutingRules []NodeRoutingRule` to:

- `types.NodeConfig`
- `types.ServerNodeConfigValues`
- `types.ServerNodeConfigOverride`
- `types.QueryServerConfigResponse`

Add server override fields:

```go
InheritRoutingRules bool              `json:"inherit_routing_rules"`
RoutingMode         string            `json:"routing_mode"`
RoutingRules        []NodeRoutingRule `json:"routing_rules"`
```

Add config fields:

```go
RoutingRules []NodeRoutingRule `yaml:"RoutingRules"`
```

For `config.NodeConfig`, use a config-local type or import-safe shape that does not create a package cycle.

- [ ] **Step 4: Implement normalization and validation**

In `backend/internal/logic/nodeconfig/override.go`, add helpers:

```go
const (
	RoutingModeInherit  = "inherit"
	RoutingModeAppend   = "append"
	RoutingModeOverride = "override"
)

func NormalizeRoutingRules(values []types.NodeRoutingRule) []types.NodeRoutingRule {
	// trim strings, dedupe string slices, drop completely empty disabled rules,
	// preserve disabled rules for admin responses.
}

func ValidateRoutingRules(rules []types.NodeRoutingRule, outbounds []types.NodeOutbound) error {
	// validate outbound_tag, at least one matcher, network, port, and known outbound tags.
}
```

Reserved outbound tags:

```go
var reservedOutboundTags = map[string]struct{}{
	"Default": {},
	"direct":  {},
	"block":   {},
	"dns_out": {},
}
```

Port validation accepts:

- `80`
- `80,443`
- `1000-2000`
- mixed comma-separated entries of single ports and ranges

Network validation accepts:

- empty
- `tcp`
- `udp`
- `tcp,udp`

- [ ] **Step 5: Run tests to verify GREEN**

Run:

```bash
go test ./internal/logic/nodeconfig
```

Expected: pass.

---

## Task 2: Backend Global and Server Merge Semantics

**Files:**

- Modify `backend/internal/logic/nodeconfig/override.go`
- Modify `backend/internal/logic/admin/system/getNodeConfigLogic.go`
- Modify `backend/internal/logic/admin/system/updateNodeConfigLogic.go`
- Modify `backend/internal/logic/admin/system/update_config.go`
- Modify `backend/internal/logic/admin/server/getServerNodeConfigLogic.go`
- Modify `backend/internal/logic/admin/server/updateServerNodeConfigLogic.go`
- Modify `backend/internal/logic/server/queryServerProtocolConfigLogic.go`
- Test `backend/internal/logic/nodeconfig/override_test.go`

- [ ] **Step 1: Write failing merge tests**

Add tests:

```go
func TestApplyRoutingRulesAppendPutsServerRulesBeforeGlobal(t *testing.T) {
	global := types.ServerNodeConfigValues{
		RoutingRules: []types.NodeRoutingRule{
			{ID: "global", Enabled: true, Sort: 10, OutboundTag: "direct", Domain: []string{"geosite:cn"}},
		},
	}
	override := types.ServerNodeConfigOverride{
		InheritRoutingRules: false,
		RoutingMode:         "append",
		RoutingRules: []types.NodeRoutingRule{
			{ID: "server", Enabled: true, Sort: 5, OutboundTag: "WARP", Domain: []string{"geosite:openai"}},
		},
	}
	effective := nodeconfig.CloneValues(global)
	err := nodeconfig.ApplyRoutingOverride(&effective, override)
	if err != nil {
		t.Fatalf("ApplyRoutingOverride() error = %v", err)
	}
	if got := effective.RoutingRules[0].ID; got != "server" {
		t.Fatalf("first rule = %q, want server", got)
	}
	if got := effective.RoutingRules[1].ID; got != "global" {
		t.Fatalf("second rule = %q, want global", got)
	}
}

func TestEffectiveRoutingRulesExcludeDisabledForNode(t *testing.T) {
	rules := []types.NodeRoutingRule{
		{ID: "off", Enabled: false, OutboundTag: "direct", Domain: []string{"geosite:cn"}},
		{ID: "on", Enabled: true, OutboundTag: "direct", Domain: []string{"geosite:google"}},
	}
	got := nodeconfig.NodeFacingRoutingRules(rules)
	if len(got) != 1 || got[0].ID != "on" {
		t.Fatalf("node-facing rules = %#v, want only enabled rule", got)
	}
}
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
go test ./internal/logic/nodeconfig
```

Expected: fail because merge helpers are missing.

- [ ] **Step 3: Implement merge helpers**

Add:

```go
func ApplyRoutingOverride(values *types.ServerNodeConfigValues, req types.ServerNodeConfigOverride) error
func NodeFacingRoutingRules(rules []types.NodeRoutingRule) []types.NodeRoutingRule
func normalizeRoutingMode(value string) string
```

Semantics:

- `inherit`: keep global rules.
- `append`: effective is server rules sorted by sort, then global rules sorted by sort.
- `override`: effective is server rules sorted by sort.
- disabled rules remain in admin responses but are filtered from node response.

- [ ] **Step 4: Wire global config read/write**

Update `GetNodeConfigLogic` and `UpdateNodeConfigLogic`:

- parse serialized `RoutingRules`
- normalize before returning
- validate before saving
- include in `convertedConfigFields`
- call `initialize.Node(l.svcCtx)` after save as current code does

- [ ] **Step 5: Wire server override read/write**

Update server node config logic:

- `GetServerNodeConfig` returns global, override, and effective routing data.
- `UpdateServerNodeConfig` validates server rules against effective outbounds.
- `UpdateServerNodeConfig` clears node cache for affected server as current logic does.

- [ ] **Step 6: Wire node pull response**

Update `QueryServerProtocolConfigLogic`:

- apply routing override after current DNS/block/outbound override.
- set `RoutingRules: nodeconfig.NodeFacingRoutingRules(nodeValues.RoutingRules)`.

- [ ] **Step 7: Run focused backend tests**

Run:

```bash
go test ./internal/logic/nodeconfig
```

Expected: pass.

---

## Task 3: Backend Persistence and API Generation

**Files:**

- Modify `backend/internal/model/node/server_config_override.go`
- Possibly add migrations in:
  - `backend/initialize/migrate/database/mysql`
  - `backend/initialize/migrate/database/postgres`
- Modify generated handlers/types only through existing generation flow if available.

- [ ] **Step 1: Inspect persistence model**

Check whether `server_config_overrides` stores discrete columns. If it does, add:

```go
RoutingMode  *string `gorm:"column:routing_mode;type:varchar(20)"`
RoutingRules *string `gorm:"column:routing_rules;type:TEXT"`
```

If a JSON/blob storage already covers extra fields, no migration is needed.

- [ ] **Step 2: Write migration tests or migration review checklist**

If columns are needed:

- MySQL migration adds nullable `routing_mode` and `routing_rules`.
- PostgreSQL migration adds nullable `routing_mode` and `routing_rules`.
- Down migration drops both columns.

Expected SQL shape:

```sql
ALTER TABLE server_config_overrides ADD COLUMN routing_mode varchar(20) NULL;
ALTER TABLE server_config_overrides ADD COLUMN routing_rules text NULL;
```

- [ ] **Step 3: Regenerate API code if project generator is required**

Run only after confirming generator is available:

```bash
cd C:\Users\pao\Documents\ppanel二开\backend
./script/generate.sh
```

On Windows, if shell execution is unavailable, manually update generated `internal/types/types.go` consistently and record generator limitation.

- [ ] **Step 4: Run backend compile/test**

Run:

```bash
go test ./internal/logic/nodeconfig ./internal/logic/server ./internal/logic/admin/system ./internal/logic/admin/server
```

Expected: pass when Go toolchain satisfies repository version.

Known environment risk: local Go is `go1.24.5`, backend requires `go 1.25.0`.

---

## Task 4: Node Routing Rule Conversion

**Files:**

- Modify `node/api/panel/server.go`
- Modify `node/core/outbound/build.go`
- Test `node/core/outbound/build_test.go`

- [ ] **Step 1: Write failing node conversion tests**

Add tests:

```go
func TestBuildAddsStructuredRoutingRuleWithInboundAndOutboundTags(t *testing.T) {
	dns := []panel.DNSItem{}
	block := []string{}
	outbound := []panel.Outbound{{Name: "WARP", Protocol: "direct"}}
	protocols := []panel.Protocol{}
	rules := []panel.RoutingRule{
		{
			ID:          "openai",
			Enabled:     true,
			Sort:        10,
			InboundTags: []string{"[https://panel.example.com]-vless:1"},
			OutboundTag: "WARP",
			Domain:      []string{"geosite:openai"},
			IP:          []string{"geoip:private"},
			Port:        "443",
			Protocol:    "bittorrent",
			Network:     "tcp",
		},
	}

	result, err := Build(&panel.ServerConfigResponse{
		Data: &panel.Data{
			IPStrategy:   "prefer_ipv4",
			DNS:          &dns,
			Block:        &block,
			Outbound:     &outbound,
			RoutingRules: &rules,
			Protocols:    &protocols,
		},
	}, false)
	if err != nil {
		t.Fatalf("Build() error = %v", err)
	}
	if got := len(result.Router.GetRule()); got != 2 {
		t.Fatalf("route rules len = %d, want DNS + structured rule", got)
	}
}
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
cd C:\Users\pao\Documents\ppanel二开\node
go test ./core/outbound
```

Expected: fail because `RoutingRule` and conversion do not exist.

- [ ] **Step 3: Add panel response type**

In `node/api/panel/server.go`:

```go
type RoutingRule struct {
	ID          string   `json:"id"`
	Enabled     bool     `json:"enabled"`
	Sort        int      `json:"sort"`
	Remark      string   `json:"remark"`
	InboundTags []string `json:"inbound_tags"`
	OutboundTag string   `json:"outbound_tag"`
	Domain      []string `json:"domain"`
	IP          []string `json:"ip"`
	Port        string   `json:"port"`
	Protocol    string   `json:"protocol"`
	Network     string   `json:"network"`
}
```

Add to `Data`:

```go
RoutingRules *[]RoutingRule `json:"routing_rules"`
```

- [ ] **Step 4: Implement router rule builder**

In `node/core/outbound/build.go`, add:

```go
func buildStructuredRoutingRule(rule panel.RoutingRule) (json.RawMessage, bool, error)
```

Build a map using Xray field names:

- `type: "field"`
- `inboundTag`: from `rule.InboundTags` when non-empty
- `outboundTag`: from `rule.OutboundTag`
- `domain`: converted through existing domain conversion helper
- `ip`: raw normalized list
- `port`: string
- `protocol`: `[]string{rule.Protocol}` when non-empty
- `network`: string

Skip disabled or empty rules.

- [ ] **Step 5: Insert structured rules after compatibility routes**

Current order stays:

1. DNS route
2. `block`
3. legacy `outbound[].rules`
4. new `routing_rules`

Because backend already places server append rules before global rules, node should preserve received order.

- [ ] **Step 6: Run node tests**

Run:

```bash
go test ./core/outbound ./core
```

Expected: pass when Go toolchain satisfies repository version.

Known environment risk: local Go is `go1.24.5`, node requires `go 1.26.1`.

---

## Task 5: Frontend Routing Rule Model

**Files:**

- Create `front/apps/admin/src/sections/servers/routing-rule-config.ts`
- Test `front/apps/admin/src/sections/servers/routing-rule-config.test.ts`
- Modify `front/packages/ui/src/services/admin/typings.d.ts`

- [ ] **Step 1: Write failing frontend model tests**

Create tests:

```ts
import { describe, expect, it } from "vitest";
import {
  normalizeRoutingRule,
  validateRoutingRule,
  buildInboundTag,
} from "./routing-rule-config";

describe("routing rule config", () => {
  it("normalizes list fields and trims tags", () => {
    const rule = normalizeRoutingRule({
      id: " cn ",
      enabled: true,
      sort: 10,
      remark: " CN ",
      inbound_tags: [" vless ", "", "vless"],
      outbound_tag: " direct ",
      domain: [" geosite:cn ", "", "geosite:cn"],
      ip: [],
      port: "",
      protocol: "",
      network: " tcp ",
    });

    expect(rule.id).toBe("cn");
    expect(rule.inbound_tags).toEqual(["vless"]);
    expect(rule.domain).toEqual(["geosite:cn"]);
    expect(rule.outbound_tag).toBe("direct");
  });

  it("builds real inbound tag from server protocol", () => {
    expect(buildInboundTag("https://panel.example.com", "vless", 1)).toBe(
      "[https://panel.example.com]-vless:1"
    );
  });

  it("rejects a rule without matchers", () => {
    expect(() =>
      validateRoutingRule({ enabled: true, outbound_tag: "direct" } as any, [
        "direct",
      ])
    ).toThrow();
  });
});
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
cd C:\Users\pao\Documents\ppanel二开\front
bun run --cwd apps/admin test routing-rule-config
```

If the repo test command does not support a file filter, run:

```bash
bun run test
```

Expected: fail because the module does not exist.

- [ ] **Step 3: Implement routing model helpers**

Create:

```ts
export type RoutingMode = "inherit" | "append" | "override";

export type RoutingRuleFormData = {
  id: string;
  enabled: boolean;
  sort: number;
  remark: string;
  inbound_tags: string[];
  outbound_tag: string;
  domain: string[];
  ip: string[];
  port: string;
  protocol: string;
  network: "" | "tcp" | "udp" | "tcp,udp";
};
```

Add:

- `routingRuleSchema`
- `normalizeRoutingRule`
- `validateRoutingRule`
- `buildInboundTag(apiHost, protocol, serverId)`
- `getReservedOutboundTags`
- `getAvailableOutboundTags(outbounds)`

- [ ] **Step 4: Run tests to verify GREEN**

Run frontend model tests again.

Expected: pass.

---

## Task 6: Frontend Routing Rule UI Component

**Files:**

- Create `front/apps/admin/src/sections/servers/routing-rule-input.tsx`
- Modify `front/apps/admin/src/sections/servers/outbound-config.ts`
- Modify `front/apps/admin/src/sections/servers/outbound-config-input.tsx`
- Test with component tests if existing setup supports React Testing Library.

- [ ] **Step 1: Write failing component tests**

Test behaviors:

- `Add Rule` opens editor.
- saving without matchers shows validation error.
- advanced mode shows real inbound tag textarea.
- outbound target options include reserved tags plus custom outbound tags.

Example:

```tsx
it("shows advanced inbound tags only when advanced mode is enabled", async () => {
  render(
    <RoutingRuleInput
      apiHost="https://panel.example.com"
      serverId={1}
      protocols={["vless"]}
      outbounds={[{ name: "WARP", protocol: "direct" } as any]}
      value={[]}
      onChange={() => {}}
    />
  );
  expect(screen.queryByText("Advanced inboundTag")).toBeNull();
  await userEvent.click(screen.getByRole("switch", { name: /advanced/i }));
  expect(screen.getByText("Advanced inboundTag")).toBeInTheDocument();
});
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
bun run --cwd apps/admin test routing-rule-input
```

Expected: fail because component is missing.

- [ ] **Step 3: Implement `RoutingRuleInput`**

Component responsibilities:

- Table/list of existing rules.
- `Add Rule`, `Edit`, `Delete`.
- fields close to 3x-ui: Domain, IP, Port, Protocol, Network, Inbound Tags, Outbound Tag, Remark, Enabled.
- default inbound selector shows protocol-friendly choices.
- advanced mode shows real `inboundTag`.
- emits normalized `RoutingRuleFormData[]`.

Use existing UI components from `@workspace/ui/components/*` and match style of `OutboundConfigInput`.

- [ ] **Step 4: Update outbound UI labels**

Keep existing outbound storage shape, but clarify label:

- Display `Tag` or `Outbound Tag` where current UI says generic `Name`.
- Preserve existing `name` JSON field for compatibility unless backend type is changed everywhere.

- [ ] **Step 5: Run component tests**

Expected: pass.

---

## Task 7: Integrate Frontend into Maintenance Xray Settings and Server Overrides

**Files:**

- Modify `front/apps/admin/src/layout/navs.ts`
- Create `front/apps/admin/src/routes/dashboard/xray-settings.lazy.tsx`
- Create `front/apps/admin/src/sections/xray-settings/index.tsx`
- Modify or reuse `front/apps/admin/src/sections/servers/server-config.tsx`
- Modify `front/apps/admin/src/sections/servers/server-node-config.tsx`
- Modify `front/packages/ui/src/services/admin/typings.d.ts`

- [ ] **Step 1: Write failing integration tests**

If existing component testing is available, add tests that:

- Maintenance navigation includes `Xray Settings` under `Maintenance`.
- `/dashboard/xray-settings` renders the global Xray settings page.
- Submit payload includes `routing_rules`.
- Per-server config has routing mode selector.
- `append` mode submits `routing_mode: "append"`.

- [ ] **Step 2: Run tests to verify RED**

Expected: fail until UI integration is implemented.

- [ ] **Step 3: Add Maintenance navigation and route**

In `layout/navs.ts`, add under `Maintenance`:

```ts
{
  title: t("Xray Settings", "Xray Settings"),
  url: "/dashboard/xray-settings",
  icon: "flat-color-icons:settings",
}
```

Create route:

```tsx
import XraySettings from "@/sections/xray-settings";
import { createLazyFileRoute } from "@tanstack/react-router";

export const Route = createLazyFileRoute("/dashboard/xray-settings")({
  component: XraySettings,
});
```

- [ ] **Step 4: Implement global Xray settings page**

In `sections/xray-settings/index.tsx`:

- Extend zod schema with `routing_rules`.
- Render tabs: `Basic`, `DNS`, `Outbounds`, `Routing Rules`, `Block`.
- Render `RoutingRuleInput`.
- Pass outbounds from current form state.
- On submit, normalize `routing_rules` and include in `updateNodeConfig`.
- Reuse existing global node config API calls from `server-config.tsx`.
- Do not remove the existing server/node management pages.

- [ ] **Step 5: Integrate per-server config**

In `server-node-config.tsx`:

- Extend schema with:
  - `inherit_routing_rules`
  - `routing_mode`
  - `routing_rules`
- Add `Routing Rules` tab.
- Render mode selector:
  - `Inherit global`
  - `Append before global`
  - `Override global`
- Render `RoutingRuleInput` only for append/override.
- Use current server protocols to build friendly inbound choices.

- [ ] **Step 6: Run frontend checks**

Run:

```bash
bun run check
bun run test
```

Expected: pass.

---

## Task 8: End-to-End Boundary Verification

**Files:**

- No new files required unless adding fixtures.

- [ ] **Step 1: Verify backend config boundary**

Use a focused backend test or HTTP-level test if existing harness supports it:

Input global rules:

```json
[
  {
    "id": "global-cn",
    "enabled": true,
    "sort": 10,
    "outbound_tag": "direct",
    "domain": ["geosite:cn"]
  }
]
```

Expected admin GET returns the same normalized rule.

- [ ] **Step 2: Verify server append boundary**

Global rule:

```json
{"id":"global-cn","sort":10,"outbound_tag":"direct","domain":["geosite:cn"]}
```

Server append rule:

```json
{"id":"server-openai","sort":5,"outbound_tag":"WARP","domain":["geosite:openai"]}
```

Expected node-facing `/v2/server/{id}` response order:

1. `server-openai`
2. `global-cn`

- [ ] **Step 3: Verify node conversion boundary**

Feed the node response fixture into `core/outbound.Build`.

Expected Xray router rules include:

- DNS rule
- legacy block/outbound rules where present
- structured rule with `outboundTag: "WARP"`
- structured rule with `inboundTag` when configured

- [ ] **Step 4: Verify frontend payload boundary**

From UI form state:

- add one global rule
- add one per-server append rule
- enable advanced inbound tag

Expected request payloads:

Global:

```json
{
  "routing_rules": [
    {
      "enabled": true,
      "outbound_tag": "direct",
      "domain": ["geosite:cn"]
    }
  ]
}
```

Per-server:

```json
{
  "inherit_routing_rules": false,
  "routing_mode": "append",
  "routing_rules": [
    {
      "enabled": true,
      "inbound_tags": ["[https://panel.example.com]-vless:1"],
      "outbound_tag": "WARP",
      "domain": ["geosite:openai"]
    }
  ]
}
```

---

## Acceptance Criteria

### Product Acceptance

- PPanel keeps its existing Node Management and Server Management structure.
- PPanel Maintenance menu contains a new `Xray Settings` module at `/dashboard/xray-settings`.
- The new module is not a replacement panel for all of PPanel and does not remove existing Server/Node pages.
- Global Xray settings page has usable `Outbounds` and `Routing Rules` controls.
- Per-server `Node Config` supports:
  - inherit global routing rules
  - append server rules before global rules
  - override global routing rules
- UI terminology is close to 3x-ui for routing fields:
  - Domain
  - IP
  - Port
  - Protocol
  - Network
  - Inbound Tags
  - Outbound Tag
  - Remark
  - Enabled
- Default UI hides raw `inboundTag`.
- Advanced mode exposes raw `inboundTag`.

### Backend Acceptance

- Global `NodeConfig` persists and returns `routing_rules`.
- Server override persists and returns `routing_mode` and `routing_rules`.
- Effective node config follows merge rules:
  - inherit = global only
  - append = server rules first, then global rules
  - override = server only
- Disabled rules remain visible to admins but are not sent to node runtime config.
- Invalid rules are rejected with clear validation errors.
- Existing `dns`, `block`, `outbound`, and `outbound[].rules` behavior remains compatible.

### Node Acceptance

- Node accepts `routing_rules` from `/v2/server/{id}` response.
- Node converts routing rules to Xray `routing.rules`.
- Generated rules include `inboundTag` when configured.
- Generated rules include `outboundTag`.
- Domain, IP, port, protocol, and network matchers are mapped correctly.
- Existing block and outbound-attached routing still works.

### Frontend Acceptance

- Global node config submit includes normalized `routing_rules`.
- Per-server node config submit includes normalized `routing_mode` and `routing_rules`.
- Form prevents:
  - missing outbound tag
  - no matcher fields
  - invalid network
  - invalid port expression
  - duplicate outbound tags
- Advanced inbound tag mode is opt-in.
- Global layout lives in the new Maintenance `Xray Settings` module.
- Per-server override layout stays embedded in existing Server Management `Node Config`.

### Verification Acceptance

Run and record:

```bash
cd C:\Users\pao\Documents\ppanel二开\front
bun run check
bun run test
```

Run if Go toolchain is upgraded enough:

```bash
cd C:\Users\pao\Documents\ppanel二开\backend
go test ./internal/logic/nodeconfig ./internal/logic/server ./internal/logic/admin/system ./internal/logic/admin/server
```

```bash
cd C:\Users\pao\Documents\ppanel二开\node
go test ./core/outbound ./core
```

If Go remains `go1.24.5`, record that backend requires `go 1.25.0` and node requires `go 1.26.1`, and do not claim Go verification passed.

## Execution Notes

- Follow TDD: write failing tests before production changes.
- Keep changes surgical inside current PPanel files.
- Do not commit without explicit user instruction.
- Add `Xray Settings` under Maintenance without replacing current node management UI.
- Preserve backward compatibility for existing node configs.
