# AnyTLS Sidecar Relay Design

## Goal

Make the imported AnyTLS subscription usable through PPanel relay ports. The existing PPanel node remains responsible for public inbound AnyTLS, user authentication, routing, and traffic accounting. A dedicated AnyTLS client sidecar handles each upstream AnyTLS connection.

## Current Evidence

- The new subscription contains 13 usable AnyTLS nodes.
- Direct `anytls-client` connection from server A to the SG upstream returned `HTTP 204`.
- The PPanel main AnyTLS inbound returned `HTTP 204`.
- PPanel relay ports `643` and `1143` reached the relay route but failed during the embedded Xray AnyTLS outbound stream.

## Architecture

```text
Client AnyTLS
    -> A:643
    -> PPanel node relay inbound
    -> PPanel SOCKS outbound to 127.0.0.1:31xxx
    -> AnyTLS sidecar
    -> upstream AnyTLS node
    -> Internet
```

Each imported upstream node gets one sidecar and one loopback SOCKS port. Public relay ports remain unchanged.

## Configuration Mapping

- Upstream address, port, password, SNI, and certificate policy come from the imported subscription.
- Sidecar loopback ports use a reserved range beginning at `31001`.
- PPanel relay rules use `target_protocol: socks`, `target_address: 127.0.0.1`, and the assigned sidecar port.
- The public AnyTLS user password remains separate from the upstream AnyTLS password.
- Existing user traffic accounting remains in the PPanel inbound and limiter path.

## Runtime Management

- A dedicated sidecar manager owns creation, update, health checking, and shutdown.
- Sidecars are started with Docker Compose and restart automatically.
- A failed sidecar is marked unhealthy and does not affect other upstream nodes.
- Subscription refresh replaces only changed sidecars and relay mappings.
- Secrets are injected through runtime configuration and are not written to logs.

## Testing and Acceptance

1. Parse the supplied subscription and create 13 sidecar definitions.
2. Verify every healthy sidecar by requesting `http://www.google.com/generate_204` through its local SOCKS port.
3. Verify at least `A:643` end to end with the public user subscription and require `HTTP 204`.
4. Verify one additional relay port, such as `1143`, end to end.
5. Restart the compose stack and confirm sidecars and relay ports recover automatically.
6. Stop one sidecar and confirm its relay fails cleanly while another relay remains healthy.
7. Confirm no upstream password appears in normal logs.

## Risks

- This adds 13 long-running client processes and corresponding health checks.
- Sidecar binaries must match the upstream AnyTLS protocol version.
- Subscription refresh must avoid leaving stale SOCKS ports or orphaned processes.
