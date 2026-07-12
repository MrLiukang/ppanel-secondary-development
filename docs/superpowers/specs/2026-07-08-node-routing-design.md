# Node Routing Design

## Goal

Add a 3x-ui-style `Xray Settings` module under PPanel's existing Maintenance menu so administrators can define Xray outbounds and routing rules from the control panel, apply them globally, and customize them per server.

## Scope

This feature covers:

- Global node routing configuration in the admin control panel.
- Per-server routing configuration with inherit, append, and override modes.
- Backend API and response model changes for routing rules.
- Node-side conversion from structured routing rules to Xray `routing.rules`.
- Admin UI module under Maintenance for outbounds and routing rules, close to 3x-ui naming and workflow.
- Tests for backend merge behavior, node config conversion, and frontend form behavior.

This feature does not cover:

- Full raw Xray JSON editing as the primary workflow.
- A general-purpose Xray config editor.
- Replacing PPanel's existing node, server, or system configuration pages.
- Rewriting PPanel to 3x-ui.
- Client subscription routing rules.
- Changing how users, subscriptions, traffic reports, or node status reporting work.

## Existing Context

The current system already has partial routing primitives:

- Backend `NodeConfig` includes `DNS`, `Block`, and `Outbound`.
- Backend server node override already supports inherited or overridden DNS, block, and outbound config.
- Node pulls server config through `/v2/server/{server_id}`.
- Node already builds default outbounds and converts current outbound-attached rules into Xray router rules.
- Frontend already has Maintenance navigation, `Node configuration`, per-server `Node Config`, and `OutboundConfigInput`.

The missing product capability is a first-class routing rule model. Current outbound-attached rules cannot clearly express 3x-ui-style rule rows with explicit `Inbound Tags`, `Outbound Tag`, ordering, enable/disable state, and per-server append behavior.

## Architecture

The design separates outgoing paths from routing decisions.

### Outbounds

Outbounds define where traffic can go.

Each outbound has:

- `tag`: the Xray outbound tag. Existing `NodeOutbound.name` can be migrated semantically to this role.
- `protocol`
- connection fields such as `address`, `port`, `user`, `password`, `uuid`, `cipher`
- security fields such as `security`, `sni`, `fingerprint`, `allow_insecure`, `reality_public_key`
- transport fields such as `transport`, `host`, `path`, `service_name`
- raw advanced fields `settings` and `stream_settings`

Built-in outbound tags are reserved:

- `Default`
- `direct`
- `block`
- `dns_out`

Custom tags must be unique and must not conflict with reserved tags.

### Routing Rules

Routing rules define when traffic uses an outbound.

Each routing rule has:

- `id`: stable UI identifier for editing lists, not required by Xray.
- `enabled`: whether the rule is active.
- `sort`: ascending order.
- `remark`: admin-facing label.
- `inbound_tags`: optional list. Empty means all inbounds.
- `outbound_tag`: required. Must reference a reserved or configured outbound tag.
- `domain`: list of domain matchers.
- `ip`: list of IP/CIDR/geoip matchers.
- `port`: optional Xray-compatible port expression, such as `80,443` or `1000-2000`.
- `protocol`: optional protocol matcher, such as `bittorrent`.
- `network`: optional `tcp`, `udp`, or `tcp,udp`.

At least one matcher among `domain`, `ip`, `port`, `protocol`, and `network` must be set.

### Global and Per-Server Rules

Global node config stores common outbounds and routing rules.

Per-server node config adds routing mode:

- `inherit`: use global routing rules only.
- `append`: put per-server rules before global rules.
- `override`: use per-server rules only.

The selected behavior is `append` when a server needs local exceptions. This is the recommended operational model because server-specific rules are usually more specific than global defaults and should match first.

## Backend API Design

No new node-facing pull endpoint is required.

### Global Admin Config

Keep existing endpoints:

- `GET /v1/admin/system/node_config`
- `PUT /v1/admin/system/node_config`

Extend `NodeConfig` with:

```json
{
  "routing_rules": [
    {
      "id": "rule-1",
      "enabled": true,
      "sort": 10,
      "remark": "CN direct",
      "inbound_tags": [],
      "outbound_tag": "direct",
      "domain": ["geosite:cn"],
      "ip": ["geoip:cn"],
      "port": "",
      "protocol": "",
      "network": ""
    }
  ]
}
```

### Per-Server Admin Config

Keep existing endpoints:

- `GET /v1/admin/server/node_config`
- `POST /v1/admin/server/node_config/update`

Extend the override model with:

```json
{
  "inherit_routing_rules": false,
  "routing_mode": "append",
  "routing_rules": []
}
```

`inherit_routing_rules` remains useful for UI consistency with existing inherit toggles. `routing_mode` defines the effective merge behavior.

### Node Pull Response

Keep existing endpoint:

- `GET /v2/server/{server_id}`

Extend the response with effective `routing_rules`.

Backend merge behavior:

- `inherit`: effective rules are global rules.
- `append`: effective rules are per-server rules followed by global rules.
- `override`: effective rules are per-server rules.

Disabled rules are stored and returned to admin endpoints, but are not included in the node-facing effective rules.

## Node Runtime Design

The node builds Xray config in this order:

1. Build default outbounds: `Default`, `block`, `dns_out`.
2. Build custom outbounds from config.
3. Build default DNS route.
4. Build compatibility `block` routes.
5. Build compatibility outbound-attached routes from legacy `outbound[].rules`.
6. Build new `routing_rules` in sort order.

For each routing rule, generate an Xray router rule:

```json
{
  "type": "field",
  "inboundTag": ["[https://panel.example.com]-vless:1"],
  "outboundTag": "direct",
  "domain": ["geosite:cn"],
  "ip": ["geoip:cn"],
  "port": "80,443",
  "protocol": ["bittorrent"],
  "network": "tcp,udp"
}
```

The real node inbound tag is currently generated as:

```text
[APIHost]-protocol:ServerId
```

Example:

```text
[https://panel.example.com]-vless:1
```

The UI should default to protocol/server-friendly choices and expose the real tag only in advanced mode.

## Frontend Design

The admin UI should stay close to 3x-ui terminology and workflow. It should be added as a new PPanel page under the existing Maintenance menu, not as a replacement for current node or server management.

### Maintenance Xray Settings

Add a new Maintenance menu item:

- title: `Xray Settings`
- route: `/dashboard/xray-settings`
- location: under `Maintenance`, alongside Server Management and Node Management

The page has routing-related tabs:

- `Basic`
- `DNS`
- `Outbounds`
- `Routing Rules`
- `Block`

`Outbounds` manages outbound tags and protocol details.

`Routing Rules` uses a 3x-ui-like rule table and add/edit dialog:

- `Enabled`
- `Remark`
- `Domain`
- `IP`
- `Port`
- `Protocol`
- `Network`
- `Inbound Tags`
- `Outbound Tag`
- order controls
- `Add Rule`
- `Edit`
- `Delete`
- `Save Settings`

### Per-Server Node Config

The existing per-server `Node Config` action keeps the same location in server management. Add routing override configuration inside that existing per-server sheet/dialog so a server can inherit, append, or override the global rules managed from `Xray Settings`.

The `Routing Rules` tab adds mode selection:

- `Inherit global`
- `Append before global`
- `Override global`

When mode is `append` or `override`, the server-level routing rule table is shown.

### Advanced Inbound Tags

Default mode:

- Show protocol/server-friendly choices such as `vless`, `trojan`, `vmess`.
- The UI maps these to real tags for the current server.

Advanced mode:

- Show actual Xray `inboundTag` values.
- Allow manual input.
- Trim and deduplicate values.
- Do not require every manually entered tag to exist, so future tag formats or custom runtime tags do not block saving.

## Validation

Backend validation:

- Rule must have `outbound_tag`.
- Rule must have at least one matcher.
- Rule `outbound_tag` must reference a reserved or configured outbound tag.
- Custom outbound tags must be unique.
- Custom outbound tags must not conflict with reserved tags.
- `network` must be empty, `tcp`, `udp`, or `tcp,udp`.
- `port` must match Xray-style single ports, comma-separated ports, or ranges.
- Empty strings are trimmed out of list fields.
- Duplicate list items are removed while preserving order.

Frontend validation:

- Prevent saving duplicate outbound tags.
- Prevent saving a routing rule without matchers.
- Prevent selecting a missing outbound tag.
- Validate port and network before submit.
- Preserve disabled rules in admin UI.

Node validation:

- Ignore disabled rules if any reach node config.
- Skip empty rules.
- Return an error for invalid raw JSON `settings` or `stream_settings`.
- Skip unsupported outbound protocols unless raw settings are provided, preserving existing behavior.

## Compatibility

Existing fields remain supported:

- `dns`
- `block`
- `outbound`
- `outbound[].rules`

Upgrade behavior:

- Old configurations continue to produce the same route behavior.
- New UI writes routing behavior to `routing_rules`.
- Existing outbound-attached rules remain visible in a compatibility area or are preserved during editing.
- Existing node versions that ignore `routing_rules` keep old behavior through existing fields.

## Testing Strategy

### Backend Tests

Add tests for:

- Global routing rules are normalized and returned.
- Per-server `inherit` returns global rules.
- Per-server `append` returns server rules before global rules.
- Per-server `override` returns only server rules.
- Disabled rules are not sent in node-facing effective config.
- Duplicate outbound tags are rejected.
- Routing rule with missing outbound tag is rejected.
- Routing rule with no matcher is rejected.
- Port and network validation.

### Node Tests

Add tests for:

- Routing rule with `inbound_tags` and `outbound_tag` generates Xray rule with `inboundTag` and `outboundTag`.
- Domain, IP, port, protocol, and network fields convert correctly.
- Rule sort order is preserved.
- Legacy `block` rules still produce block routing.
- Legacy `outbound[].rules` still produce outbound routing.
- Custom outbound tags are available before routing rules reference them.

### Frontend Tests

Add tests for:

- Routing rule form rejects missing matchers.
- Routing rule form rejects missing outbound tag.
- Global node config submit includes `routing_rules`.
- Per-server append mode submit includes `routing_mode: "append"` and rule payload.
- Advanced mode shows real inbound tags.
- Default mode maps protocol-friendly choices to current server inbound tags.

### Verification Commands

Frontend:

```bash
bun run check
bun run test
```

Backend:

```bash
go test ./internal/logic/nodeconfig ./internal/logic/server ./internal/logic/admin/system ./internal/logic/admin/server
```

Node:

```bash
go test ./core/outbound ./core
```

Environment note: current local Go version is `go1.24.5`, while backend requires `go 1.25.0` and node requires `go 1.26.1`. If Go is not upgraded before implementation verification, Go tests may fail or trigger toolchain behavior unrelated to this feature.

## Open Decisions Resolved

- Feature style: 3x-ui-like routing management, not raw Xray JSON-first.
- Rule model: independent routing rules separate from outbounds.
- `inboundTag`/`outboundTag`: supported; advanced UI exposes real `inboundTag`.
- Scope: global rules plus per-server inherit, append, or override.
- Merge order for append: per-server rules before global rules.
