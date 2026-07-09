# 3x-ui Routing Design for PPanel

## Goal

Add 3x-ui-style Xray routing management to PPanel so operators can configure routing rules from the control panel, have those rules delivered to ppanel-node, and have node generate effective Xray `routing.rules`.

This feature targets the 3x-ui `/panel/routing` route rule capability. It does not create new listener ports by itself. A rule such as `node1:643 -> hknode:6443` requires that the `node1:643` inbound and the `hknode:6443` outbound already exist or are created by another node/inbound feature.

## Observed 3x-ui Behavior

The inspected 3x-ui routing page contains three areas:

1. Basic routing
   - Block BitTorrent protocol.
   - Block IP lists such as private IP ranges.
   - Block domain lists.
   - Direct IP lists.
   - Direct domain lists.
   - IPv4 routing toggle.

2. Route rules
   - Table columns: action, enabled, network, destination, inbound, outbound.
   - Rule editor fields: enabled, source IP, source port, VLESS route, network, protocol, attrs, IP, domain, user, port, inbound tags, outbound tag, balancer tag.

3. Route test
   - Inputs: domain or IP, port, network, inbound, sniffing protocol.
   - It queries running Xray routing without sending real traffic.

## Scope

Phase one implements route rule parity and basic routing shortcuts:

- Extend PPanel route rule data with 3x-ui core fields:
  - `source_ip`
  - `source_port`
  - `user`
  - `attrs`
  - `vless_route`
  - `balancer_tag`
- Keep existing PPanel fields:
  - `id`
  - `enabled`
  - `sort`
  - `remark`
  - `inbound_tags`
  - `outbound_tag`
  - `domain`
  - `ip`
  - `port`
  - `protocol`
  - `network`
- Convert enabled rules into Xray routing rule JSON on ppanel-node.
- Keep routing storage in the existing server `RoutingRules` system config and per-server override path.
- Add basic routing shortcuts in the UI that generate or maintain normal route rules instead of introducing a separate storage model.

Phase one excludes route testing. Route testing requires a node-side live Xray route query API and a control-panel proxy endpoint. That should be implemented after rule delivery is stable.

## Product Behavior

Operators manage routing under PPanel admin maintenance Xray settings.

The global Xray Settings page controls default routing for all nodes. Each server's node config page can inherit global routing or override it, following the existing override pattern.

The route rules UI should be closer to 3x-ui:

- Show rules in a dense table with columns for enabled state, network, destination summary, inbound summary, and outbound summary.
- Create and edit rules in a modal or drawer.
- Keep an advanced section for less common fields such as source IP, source port, user, attrs, VLESS route, and balancer tag.
- Preserve existing outbounds and reserved tags in outbound selection.
- Sort by `sort` before delivery to nodes.

Basic routing shortcuts should be presented as a separate tab or section:

- Block BitTorrent maps to an enabled rule with `protocol: bittorrent` and `outbound_tag: block`.
- Block IP maps to rules with `ip` values and `outbound_tag: block`.
- Block domain maps to rules with `domain` values and `outbound_tag: block`.
- Direct IP maps to rules with `ip` values and `outbound_tag: direct`.
- Direct domain maps to rules with `domain` values and `outbound_tag: direct`.
- IPv4 route maps to an enabled rule with Xray-compatible network/IP criteria only if the current node builder can express it without raw JSON. If not, the UI should not expose this toggle in phase one.

## Data Model

The API-facing `NodeRoutingRule` is extended as follows:

```json
{
  "id": "rule-1",
  "enabled": true,
  "sort": 1,
  "remark": "Private IP block",
  "source_ip": ["geoip:private"],
  "source_port": "1000-2000",
  "vless_route": "",
  "network": "tcp",
  "protocol": "bittorrent",
  "attrs": "attrs[':method'] == 'GET'",
  "domain": ["geosite:cn"],
  "ip": ["geoip:private"],
  "user": ["user@example.com"],
  "port": "443",
  "inbound_tags": ["node1-643"],
  "outbound_tag": "block",
  "balancer_tag": ""
}
```

Compatibility rules:

- Existing saved rules without new fields remain valid.
- Empty string and empty array fields are omitted when node builds Xray JSON.
- A rule must have either `outbound_tag` or `balancer_tag`.
- A rule with no match criteria after normalization is ignored.
- If both `outbound_tag` and `balancer_tag` are set, validation rejects the rule because Xray route rules should choose one target.

## Backend

Backend changes stay inside existing node config boundaries.

Types to extend:

- `backend/internal/types/types.go`
- `backend/internal/config/config.go`
- generated API type files if the project requires regeneration from `.api` definitions
- `backend/apis/types.api`
- `backend/apis/node/node.api`
- `backend/apis/admin/server.api`

Validation changes:

- Extend existing route rule validation to accept the new fields.
- Validate `source_port` and `port` as comma-separated ports or ranges.
- Validate `network` as empty, `tcp`, `udp`, or `tcp,udp`.
- Validate target selection: exactly one of `outbound_tag` or `balancer_tag` is required for enabled rules.
- Validate `outbound_tag` against reserved tags plus configured custom outbound tags.
- Allow `balancer_tag` as a free-form non-empty string because balancer definitions are outside phase-one scope.

Persistence:

- Keep storing `RoutingRules` as JSON in the existing system config row and server override table.
- No schema migration is required for new fields because JSON is already stored in text columns.

## Node

ppanel-node already receives `routing_rules` and builds Xray route JSON.

Node changes:

- Extend `node/api/panel/server.go` `RoutingRule`.
- Extend `node/core/outbound/build.go` rule generation.
- Include these Xray JSON fields when present:
  - `source`
  - `sourcePort`
  - `user`
  - `attrs`
  - `inboundTag`
  - `outboundTag`
  - `balancerTag`
  - `domain`
  - `ip`
  - `port`
  - `protocol`
  - `network`
- Reject or skip invalid rules before they reach Xray build.

The node builder must keep current behavior for existing rules and tests.

## Frontend

Frontend changes stay in the existing admin app.

Files likely to change:

- `front/apps/admin/src/sections/xray-settings/routing-rules-input.tsx`
- `front/apps/admin/src/sections/xray-settings/index.tsx`
- `front/apps/admin/src/sections/servers/server-node-config.tsx`
- `front/apps/admin/src/sections/servers/server-config.tsx`
- `front/packages/ui/src/services/*/typings.d.ts`
- locale JSON for server routing labels

UI behavior:

- Replace or augment the current accordion with a 3x-ui-like table.
- Use a modal or drawer for editing one rule.
- Show common fields first: enabled, remark, network, domain, IP, port, protocol, inbound tags, outbound tag.
- Put advanced fields behind an advanced section: source IP, source port, user, attrs, VLESS route, balancer tag.
- Preserve the existing advanced-mode decision: advanced-only fields are shown only in advanced mode.

Basic routing shortcuts should produce ordinary route rules with stable IDs:

- `basic-block-bittorrent`
- `basic-block-ip`
- `basic-block-domain`
- `basic-direct-ip`
- `basic-direct-domain`

This keeps the API and node builder simple.

## Testing

Backend tests:

- Existing rule validation accepts old rules.
- Validation accepts new 3x-ui-style fields.
- Validation rejects enabled rules with both `outbound_tag` and `balancer_tag`.
- Validation rejects enabled rules with neither target.
- Validation rejects invalid port ranges.

Node tests:

- Existing route rule tests continue passing.
- A rule with `source_ip`, `source_port`, `user`, `attrs`, and `balancer_tag` builds expected Xray route JSON.
- A rule with `inbound_tags: ["node1-643"]` and `outbound_tag: "hknode-6443"` builds an Xray rule targeting `hknode-6443`.
- Disabled rules are skipped.

Frontend tests:

- Routing rule editor renders common fields.
- Advanced mode reveals source IP, source port, user, attrs, VLESS route, and balancer tag.
- Saving a rule emits the expected `NodeRoutingRule` shape.
- Basic routing shortcuts emit stable generated rules.

Verification commands:

- `go test ./...` in `backend`
- `go test ./...` in `node`
- relevant frontend test or typecheck command in `front`
- `git diff --check`

## Acceptance Criteria

- Admin can create and edit 3x-ui-style route rules in PPanel.
- Global Xray Settings and server-specific override both support the extended rule shape.
- ppanel-node receives the extended rule shape and generates Xray `routing.rules`.
- Existing rules remain backward compatible.
- `node1-643 -> hknode-6443` can be represented when the inbound tag and outbound tag already exist.
- Tests cover validation, node rule generation, and frontend form output.

## Out of Scope

- Creating new inbound listener ports such as `node1:643`.
- Creating outbound definitions automatically from server names.
- Live route testing against running Xray.
- Balancer definition management.
