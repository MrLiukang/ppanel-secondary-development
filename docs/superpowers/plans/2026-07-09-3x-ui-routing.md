# 3x-ui Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 3x-ui-style Xray routing rule fields to PPanel, deliver them to ppanel-node, and expose them in the admin UI.

**Architecture:** Keep routing rules in the existing `RoutingRules` JSON config path. Backend validates and normalizes the extended rule shape, node converts the shape into Xray routing JSON, and frontend edits the same API object with common and advanced fields.

**Tech Stack:** Go backend, Go ppanel-node, React/Bun admin frontend, existing PPanel API typings.

---

### Task 1: Backend Routing Rule Model And Validation

**Files:**
- Modify: `backend/internal/types/types.go`
- Modify: `backend/internal/config/config.go`
- Modify: `backend/apis/types.api`
- Modify: `backend/internal/logic/nodeconfig/override.go`
- Test: `backend/internal/logic/nodeconfig/override_test.go`

- [ ] **Step 1: Write failing backend tests**

Add tests that assert new fields survive normalization and that target selection is validated:

```go
func TestRoutingRuleNormalizationPreserves3XUIFields(t *testing.T) {
	rules := NormalizeRoutingRules([]types.NodeRoutingRule{{
		ID:          "advanced",
		Enabled:     true,
		Sort:        1,
		SourceIP:    []string{"geoip:private", ""},
		SourcePort:  "1000-2000",
		VlessRoute:  "443",
		Network:     "tcp",
		Protocol:    "bittorrent",
		Attrs:       "attrs[':method'] == 'GET'",
		IP:          []string{"geoip:cn"},
		Domain:      []string{"geosite:cn"},
		User:        []string{"user@example.com", ""},
		Port:        "443",
		InboundTags: []string{"node1-643", ""},
		BalancerTag: "balancer-a",
	}})
	if len(rules) != 1 {
		t.Fatalf("rules len = %d, want 1", len(rules))
	}
	got := rules[0]
	if got.SourceIP[0] != "geoip:private" || len(got.SourceIP) != 1 {
		t.Fatalf("SourceIP = %#v", got.SourceIP)
	}
	if got.SourcePort != "1000-2000" || got.VlessRoute != "443" || got.Attrs == "" {
		t.Fatalf("advanced fields not preserved: %#v", got)
	}
	if len(got.User) != 1 || got.User[0] != "user@example.com" {
		t.Fatalf("User = %#v", got.User)
	}
	if got.BalancerTag != "balancer-a" {
		t.Fatalf("BalancerTag = %q", got.BalancerTag)
	}
}

func TestValidateRoutingRulesRejectsBothOutboundAndBalancer(t *testing.T) {
	err := ValidateRoutingRules(
		[]types.NodeRoutingRule{{
			Enabled:     true,
			Domain:      []string{"geosite:cn"},
			OutboundTag: "direct",
			BalancerTag: "balancer-a",
		}},
		nil,
	)
	if err == nil {
		t.Fatal("ValidateRoutingRules() error = nil, want target conflict")
	}
}

func TestValidateRoutingRulesAcceptsBalancerTarget(t *testing.T) {
	err := ValidateRoutingRules(
		[]types.NodeRoutingRule{{
			Enabled:     true,
			InboundTags: []string{"node1-643"},
			BalancerTag: "balancer-a",
		}},
		nil,
	)
	if err != nil {
		t.Fatalf("ValidateRoutingRules() error = %v", err)
	}
}
```

- [ ] **Step 2: Run backend test to verify failure**

Run:

```bash
go test ./internal/logic/nodeconfig -run 'TestRoutingRuleNormalizationPreserves3XUIFields|TestValidateRoutingRulesRejectsBothOutboundAndBalancer|TestValidateRoutingRulesAcceptsBalancerTarget' -count=1
```

Expected: compile failure for missing fields such as `SourceIP` and `BalancerTag`.

- [ ] **Step 3: Implement backend fields and validation**

Add fields to every backend `NodeRoutingRule` type:

```go
SourceIP    []string `json:"source_ip"`
SourcePort  string   `json:"source_port"`
VlessRoute  string   `json:"vless_route"`
Attrs       string   `json:"attrs"`
User        []string `json:"user"`
BalancerTag string   `json:"balancer_tag"`
```

Normalize list fields with the existing string-list helper and trim string fields. Update `isEmptyRoutingRule` and `hasRoutingMatcher` so source fields, user, attrs, and VLESS route count as rule content. Update validation so enabled rules require exactly one target: `outbound_tag` or `balancer_tag`.

- [ ] **Step 4: Run backend tests and commit**

Run:

```bash
go test ./internal/logic/nodeconfig -count=1
```

Expected: PASS.

Commit in `backend`:

```bash
git add internal/types/types.go internal/config/config.go apis/types.api internal/logic/nodeconfig/override.go internal/logic/nodeconfig/override_test.go
git commit -m "feat: extend routing rule validation"
```

### Task 2: Node Xray Route Rule Generation

**Files:**
- Modify: `node/api/panel/server.go`
- Modify: `node/core/outbound/build.go`
- Test: `node/core/outbound/build_test.go`

- [ ] **Step 1: Write failing node test**

Add a test that builds an advanced route rule and checks the generated Xray JSON:

```go
func TestBuildAdds3XUIRoutingFields(t *testing.T) {
	routingRules := []panel.RoutingRule{{
		ID:          "advanced",
		Enabled:     true,
		SourceIP:    []string{"geoip:private"},
		SourcePort:  "1000-2000",
		User:        []string{"user@example.com"},
		Attrs:       "attrs[':method'] == 'GET'",
		InboundTags: []string{"node1-643"},
		BalancerTag: "balancer-a",
	}}
	result, err := Build(&panel.ServerConfigResponse{
		Data: &panel.ServerConfig{
			Outbound:     &[]panel.Outbound{},
			RoutingRules: &routingRules,
		},
	}, false)
	if err != nil {
		t.Fatalf("Build() error = %v", err)
	}
	raw := result.Router.Rule[len(result.Router.Rule)-1].Rule
	var rule map[string]interface{}
	if err := json.Unmarshal(raw, &rule); err != nil {
		t.Fatalf("unmarshal route rule: %v", err)
	}
	if got := rule["balancerTag"]; got != "balancer-a" {
		t.Fatalf("balancerTag = %v", got)
	}
	if got := rule["sourcePort"]; got != "1000-2000" {
		t.Fatalf("sourcePort = %v", got)
	}
}
```

- [ ] **Step 2: Run node test to verify failure**

Run:

```bash
go test ./core/outbound -run TestBuildAdds3XUIRoutingFields -count=1
```

Expected: compile failure for missing `SourceIP`, `SourcePort`, `User`, `Attrs`, or `BalancerTag`.

- [ ] **Step 3: Implement node fields and JSON generation**

Add the same fields to `panel.RoutingRule`. In `buildRoutingRule`, write:

```go
if source := normalizeStringList(item.SourceIP); len(source) > 0 {
	rule["source"] = source
}
if sourcePort := strings.TrimSpace(item.SourcePort); sourcePort != "" {
	rule["sourcePort"] = sourcePort
}
if users := normalizeStringList(item.User); len(users) > 0 {
	rule["user"] = users
}
if attrs := strings.TrimSpace(item.Attrs); attrs != "" {
	rule["attrs"] = attrs
}
if balancerTag := strings.TrimSpace(item.BalancerTag); balancerTag != "" {
	rule["balancerTag"] = balancerTag
} else {
	rule["outboundTag"] = outboundTag
}
```

Keep existing outbound behavior for rules without a balancer.

- [ ] **Step 4: Run node tests and commit**

Run:

```bash
go test ./core/outbound -count=1
```

Expected: PASS.

Commit in `node`:

```bash
git add api/panel/server.go core/outbound/build.go core/outbound/build_test.go
git commit -m "feat: support 3x-ui routing fields"
```

### Task 3: Frontend Routing Rule Editor

**Files:**
- Modify: `front/apps/admin/src/sections/xray-settings/routing-rules-input.tsx`
- Modify: `front/packages/ui/src/services/admin/typings.d.ts`
- Modify: other generated service typings containing `NodeRoutingRule` if compilation requires it

- [ ] **Step 1: Extend frontend types**

Add optional fields to `API.NodeRoutingRule` typings:

```ts
source_ip: string[];
source_port: string;
vless_route: string;
attrs: string;
user: string[];
balancer_tag: string;
```

- [ ] **Step 2: Update normalization and creation**

Make new rules initialize all new fields as empty arrays or empty strings. Make `normalizeRule` preserve all new fields.

- [ ] **Step 3: Add advanced editor controls**

Add advanced-only controls to the existing routing rule editor:

- Source IP textarea.
- Source port input.
- VLESS route input.
- Attrs textarea.
- User textarea.
- Balancer tag input.

Keep common fields visible exactly as they are now.

- [ ] **Step 4: Run frontend verification and commit**

Run:

```bash
bun run check
```

If the repository check is too broad or already failing outside this change, run the narrowest available admin typecheck or lint command and record the failure boundary.

Commit in `front`:

```bash
git add apps/admin/src/sections/xray-settings/routing-rules-input.tsx packages/ui/src/services/admin/typings.d.ts
git commit -m "feat: expose 3x-ui routing fields"
```

### Task 4: Final Verification

**Files:**
- No new files expected.

- [ ] **Step 1: Run backend focused tests**

```bash
go test ./internal/logic/nodeconfig -count=1
```

- [ ] **Step 2: Run node focused tests**

```bash
go test ./core/outbound -count=1
```

- [ ] **Step 3: Run diff checks**

```bash
git -C backend diff --check
git -C node diff --check
git -C front diff --check
```

- [ ] **Step 4: Report status**

Report commits, tests run, and any verification that could not be run.
