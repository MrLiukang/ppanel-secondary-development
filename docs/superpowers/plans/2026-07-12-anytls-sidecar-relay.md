# AnyTLS Sidecar Relay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax and require verification before each commit.

**Goal:** Route imported AnyTLS subscription nodes through local `anytls-client` SOCKS sidecars so PPanel relay ports work end to end.

**Architecture:** The backend stores both the public relay mapping and the upstream AnyTLS sidecar parameters. A small sidecar supervisor launches one pinned `anytls-client` process per enabled AnyTLS upstream and exposes loopback SOCKS ports. Node relay rules target those SOCKS ports, keeping public AnyTLS authentication and traffic accounting in PPanel.

**Tech Stack:** Existing Go backend, Go node protocol types, Docker Compose, `anytls-client` Linux binary, MySQL JSON relay configuration, focused Go tests, and remote curl-based integration tests.

---

### Task 1: Define sidecar relay data contract

**Files:**
- Modify: `backend/apis/types.api`
- Modify: `backend/internal/types/types.go`
- Modify: `node/api/panel/server.go`
- Test: `backend/internal/logic/nodeconfig/*_test.go`

- [ ] Add explicit fields to relay rules: `sidecar_enabled`, `sidecar_port`, and upstream fields `target_protocol`, `target_address`, `target_port`, `target_password`, `target_sni`, `target_allow_insecure`.
- [ ] Preserve JSON compatibility so existing AnyTLS rules without sidecar fields continue to decode as direct relay rules.
- [ ] Add tests proving AnyTLS upstream fields survive API serialization and that SOCKS relay mappings are accepted.
- [ ] Run `GOEXPERIMENT=jsonv2 go test ./internal/logic/nodeconfig ./internal/logic/admin/server` in the backend Docker toolchain.
- [ ] Commit the contract-only change with `feat: define anytls sidecar relay contract`.

### Task 2: Build the sidecar supervisor

**Files:**
- Create: `tools/anytls-sidecar/main.go`
- Create: `tools/anytls-sidecar/config.go`
- Create: `tools/anytls-sidecar/supervisor.go`
- Create: `tools/anytls-sidecar/supervisor_test.go`
- Create: `tools/anytls-sidecar/Dockerfile`

- [ ] Implement config loading for server URL, server ID, secret key, binary path, and loopback port range.
- [ ] Fetch relay rules from `GET /v2/server/{server_id}` using the existing `secret_key` query contract.
- [ ] Select enabled `target_protocol=anytls` rules, assign deterministic sidecar ports from `31001`, and start one `anytls-client` process per rule.
- [ ] Pass upstream password and SNI only through process arguments; redact them from supervisor logs.
- [ ] Restart a child after exit with bounded backoff and terminate stale children when a rule is removed.
- [ ] Add tests for deterministic port assignment, argument construction, secret redaction, and child restart behavior.
- [ ] Run `go test ./tools/anytls-sidecar/...` and build the Docker image.
- [ ] Commit with `feat: add anytls sidecar supervisor`.

### Task 3: Generate SOCKS relay mappings

**Files:**
- Modify: `backend/internal/logic/nodeconfig/*`
- Modify: `backend/internal/model/node/*`
- Test: `backend/internal/logic/nodeconfig/*_test.go`

- [ ] When importing AnyTLS subscription nodes, retain upstream fields for the supervisor and set the node-facing relay mapping to `target_protocol=socks`, `target_address=127.0.0.1`, and the assigned `sidecar_port`.
- [ ] Keep public listen ports stable, preserving the current `643`, `743`, `843` sequence.
- [ ] Exclude subscription metadata entries such as traffic and expiry pseudo-nodes.
- [ ] Ensure refresh updates changed sidecars without changing user-facing node passwords.
- [ ] Add tests for 13-node import, stable port mapping, metadata filtering, and refresh idempotency.
- [ ] Run the focused backend test suite and `git diff --check`.
- [ ] Commit with `feat: map anytls relays through local socks sidecars`.

### Task 4: Add production Docker integration

**Files:**
- Modify: `docker-local/production/docker-compose.yml`
- Create: `docker-local/production/anytls-sidecar.Dockerfile`
- Create: `docker-local/production/anytls-sidecar.yml`
- Modify: `docker-local/production/ppanel.yaml`
- Modify: `docs/superpowers/specs/2026-07-12-anytls-sidecar-relay-design.md`

- [ ] Add the sidecar supervisor with host networking so its SOCKS listeners are reachable by `production-node` on `127.0.0.1`.
- [ ] Mount the pinned `anytls-client` binary read-only and pass the PPanel API endpoint and node secret through environment variables.
- [ ] Add restart policy and health checks that verify the supervisor process and at least one configured local SOCKS listener.
- [ ] Ensure the supervisor starts after PPanel and does not expose its control API publicly.
- [ ] Build and start an isolated local compose project.
- [ ] Verify all containers start and the sidecar supervisor creates the expected loopback listeners.
- [ ] Commit with `feat: deploy anytls sidecars with production compose`.

### Task 5: Deploy and verify end to end

**Files:**
- Modify: `docs/superpowers/plans/2026-07-12-anytls-sidecar-relay.md`

- [ ] Build backend, node, and sidecar images with pinned inputs.
- [ ] Upload the images and sidecar binary to `204.0.56.168` and restart only the affected services.
- [ ] Pull the public user subscription and verify the new relay nodes contain the expected listen ports and public AnyTLS SNI.
- [ ] Test the sidecar directly: `anytls-client -> local SOCKS -> www.google.com/generate_204`, expecting `HTTP 204`.
- [ ] Test the public path: `AnyTLS client -> A:643 -> PPanel relay -> local SOCKS sidecar -> upstream`, expecting `HTTP 204`.
- [ ] Repeat for `1143` and one non-SG node.
- [ ] Restart the compose stack and repeat the `643` test to verify recovery.
- [ ] Stop one sidecar and verify only its relay fails while another relay remains healthy.
- [ ] Confirm logs redact upstream passwords and report exact command output for every acceptance check.
- [ ] Commit the verified implementation with `feat: enable anytls sidecar relay in production`.
