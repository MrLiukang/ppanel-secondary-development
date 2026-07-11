# Subscription Relay Import Design

## Goal

Allow an operator to paste an external client subscription URL, preview usable proxy nodes from that subscription, and import selected nodes as PPanel `relay_rules` on an entry server.

The target workflow is:

```text
A entry node listen :643 -> external HK VLESS/TLS/XHTTP node
A entry node listen :743 -> external TW or JP VLESS/TLS/XHTTP node
```

This extends the existing Xray Settings / relay rules work. It does not replace the current `xray-settings` module and does not rewrite PPanel routing.

## Confirmed Context

The current relay feature can already create extra listeners on an entry node and route each listener to a configured target outbound. It supports the main target fields needed by AnyTLS, VLESS, Trojan, TCP, WS, gRPC, HTTP upgrade, SplitHTTP, and XHTTP through the node outbound builder.

The tested external subscription returns Base64 subscription content containing mostly `vless://` nodes using:

- protocol: `vless`
- transport: `xhttp`
- security: `tls`
- port: `443`
- query field: `allowInsecure=1`
- query fields such as `sni`, `path`, and optional host header

The current relay model does not preserve `allowInsecure`, so importing these nodes without adding that field can produce an outbound TLS verification failure.

## Scope

In scope:

- Add `target_allow_insecure` to relay rules.
- Deliver `target_allow_insecure` from backend config to ppanel-node.
- Make ppanel-node set outbound TLS `AllowInsecure` from the relay rule.
- Add backend subscription preview parsing for admin use.
- Parse Base64 subscription bodies and plain newline proxy-link bodies.
- Support `vless://` and `trojan://` links for import.
- Skip unusable subscription entries such as host `0.0.0.0`.
- Add an admin UI import dialog in the relay rules editor.
- Let operators choose a start listen port and import selected preview rows into relay rules.
- Do not store the subscription URL or token after preview.

Out of scope:

- Changing normal user subscription output.
- Replacing PPanel server/node creation.
- Automatically testing real external proxy traffic through third-party nodes.
- Storing or refreshing subscription URLs on a schedule.
- Balancer pools.
- Per-user traffic attribution on the exit node. Traffic accounting remains entry-side for this pass.

## Architecture

Backend owns subscription fetching and parsing because browser-side fetch can be blocked by CORS. The admin frontend calls a preview endpoint with a URL and import options. Backend fetches the URL with timeout and response-size limits, decodes subscription content if needed, parses supported proxy links, and returns candidate relay rules plus skip reasons.

The frontend never stores the original URL. It shows the preview rows and appends selected candidates into the existing relay rule form state. Saving still uses the existing node config save path.

The node runtime remains simple. It only consumes `relay_rules`. It does not know where a rule came from.

## Data Model

Extend `NodeRelayRule` in backend, frontend, and node:

```json
{
  "target_allow_insecure": true
}
```

Default value is `false`. Existing saved rules without this field keep the current behavior.

Subscription candidates map into relay rules:

| Subscription field | Relay rule field |
| --- | --- |
| scheme `vless` | `target_protocol: "vless"` |
| scheme `trojan` | `target_protocol: "trojan"` |
| userinfo UUID/password | `target_uuid` for VLESS, `target_password` for Trojan |
| host | `target_address` |
| port | `target_port` |
| query `type` | `target_transport` |
| query `security` | `target_security` |
| query `sni` | `target_sni` |
| query `host` | `target_host` |
| query `path` | `target_path` |
| query `allowInsecure` | `target_allow_insecure` |
| fragment name | `remark` |

## Backend Behavior

Add an admin-only preview endpoint under the existing admin API style. The endpoint accepts:

```json
{
  "url": "https://example.com/api/v1/client/subscribe?token=...",
  "listen_port_start": 643,
  "listen_port_step": 100
}
```

It returns:

```json
{
  "rules": [
    {
      "id": "relay-import-hk1-643",
      "enabled": true,
      "sort": 1,
      "remark": "HK 1",
      "listen_port": 643,
      "network": "tcp,udp",
      "target_address": "hk1.example.com",
      "target_port": 443,
      "target_protocol": "vless",
      "target_security": "tls",
      "target_transport": "xhttp",
      "target_sni": "update.microsoft.com",
      "target_path": "/path",
      "target_uuid": "uuid-value",
      "target_allow_insecure": true
    }
  ],
  "skipped": [
    {
      "name": "notice",
      "reason": "invalid target address 0.0.0.0"
    }
  ]
}
```

The fetcher should use a short timeout and cap response size to avoid large downloads. The response should not log or persist subscription credentials.

## Frontend Behavior

In the relay rules editor:

- Add a `从订阅导入` button.
- Open a dialog with fields:
  - subscription URL
  - start listen port
  - listen port step
- Show preview rows with:
  - selected checkbox
  - generated listen port
  - node name
  - target host and port
  - protocol / transport / security
  - SNI
  - allow insecure status
- Append selected rows into the existing relay rule list.
- Show skip reasons in the dialog.

Advanced mode should show `允许不安全 TLS` together with SNI/security fields.

## Testing

Backend tests:

- Parse Base64 subscriptions.
- Map VLESS XHTTP TLS links into relay rules.
- Preserve `allowInsecure=1`.
- Skip `0.0.0.0` Trojan placeholders.

Node tests:

- A relay rule with `target_allow_insecure: true` produces an outbound stream TLS config with `allowInsecure: true`.

Frontend verification:

- Type/build check succeeds.
- Dialog can preview rows from the backend response and append selected rows to relay rules.

Docker verification:

- Rebuild backend and admin web images.
- Confirm admin UI still loads.
- Confirm node config response includes imported relay rules.

