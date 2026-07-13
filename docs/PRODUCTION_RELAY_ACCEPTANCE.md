# Production relay installation acceptance

## Automated checks

Run from the repository root on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-production-assets.ps1
```

Run on the Linux production host:

```sh
bash scripts/verify-production-assets.sh
sudo bash scripts/install-production.sh
docker compose -f docker-local/production/docker-compose.yml exec anytls-sidecar-manager /usr/local/bin/anytls-client -h
sudo test -x /opt/ppanel/anytls-client
docker compose -f docker-local/production/docker-compose.yml ps
docker ps --filter name=ppanel-relay-sidecar
```

The production manager image builds `anytls-client` from the official
`https://github.com/anytls/anytls-go.git` repository at pinned commit
`9666872946857b50a74fdb692896d77b53773cb2` using its `./cmd/client` package.
The build verifies `git rev-parse HEAD` before compiling. Xray is pinned to
`v26.3.27`, and its archive is checked against the architecture-specific
SHA256 before extraction. Base images are pinned to multi-architecture manifest
digests.

At container startup, the entrypoint installs the image asset into
`/opt/ppanel/anytls-client` only when that path does not exist. An existing user
binary is preserved. If installation fails, AnyTLS health is explicitly
`degraded`/unavailable while Trojan and Shadowsocks remain eligible to run; the
manager process continues so this is not reported as whole-manager health.

## Checks requiring a real server

1. Start with a host where `/opt/ppanel/anytls-client` does not exist and verify the manager creates an executable file there.
2. Import one working AnyTLS, Trojan, and Shadowsocks upstream and verify each local SOCKS listener returns HTTP 204 through its own upstream.
3. Temporarily make the AnyTLS asset unavailable, restart the manager, and verify Trojan and Shadowsocks listeners remain healthy while only AnyTLS reports failure.
4. Restart Docker and then the host; verify the unified `ppanel-relay-sidecar` and all valid rule processes recover.
5. Verify the public relay path for each protocol, including node authentication, traffic accounting, health reporting, and user-visible node state.
