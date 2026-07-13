#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$ROOT_DIR/docker-local/production/anytls-sidecar-manager.Dockerfile"
ENTRYPOINT="$ROOT_DIR/scripts/relay-sidecar-manager-entrypoint.sh"
COMPOSE_FILE="$ROOT_DIR/docker-local/production/docker-compose.yml"
ACCEPTANCE_DOC="$ROOT_DIR/docs/PRODUCTION_RELAY_ACCEPTANCE.md"
MANAGER_SOURCE="$ROOT_DIR/backend/tools/anytls-sidecar-manager/main.go"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }
require_match() {
  local pattern="$1" file="$2" description="$3"
  grep -Eq "$pattern" "$file" || fail "$description"
}

[[ -f "$DOCKERFILE" ]] || fail "production sidecar Dockerfile is missing"
[[ -f "$ENTRYPOINT" ]] || fail "sidecar manager entrypoint is missing"
[[ -f "$COMPOSE_FILE" ]] || fail "production Compose file is missing"

require_match '^ARG ANYTLS_COMMIT=[0-9a-f]{40}$' "$DOCKERFILE" \
  "AnyTLS source is not pinned to an immutable commit"
require_match 'https://github\.com/anytls/anytls-go\.git' "$DOCKERFILE" \
  "AnyTLS client source is not the official repository"
require_match 'git checkout .*\$\{ANYTLS_COMMIT\}' "$DOCKERFILE" \
  "AnyTLS source checkout does not use the declared commit"
require_match 'git rev-parse HEAD.*ANYTLS_COMMIT|ANYTLS_COMMIT.*git rev-parse HEAD' "$DOCKERFILE" \
  "AnyTLS build does not verify the checked-out commit"
require_match 'org\.opencontainers\.image\.anytls\.commit=.*ANYTLS_COMMIT' "$DOCKERFILE" \
  "final image does not expose the verified AnyTLS commit"
require_match 'go build .*\./cmd/client' "$DOCKERFILE" \
  "AnyTLS client package is not built into the image asset"
require_match '^ARG XRAY_VERSION=v[0-9]+\.[0-9]+\.[0-9]+$' "$DOCKERFILE" \
  "Xray version is not pinned"
require_match '^ARG XRAY_SHA256_AMD64=[0-9a-f]{64}$' "$DOCKERFILE" \
  "Xray amd64 SHA256 is not pinned"
require_match '^ARG XRAY_SHA256_ARM64=[0-9a-f]{64}$' "$DOCKERFILE" \
  "Xray arm64 SHA256 is not pinned"
require_match 'releases/download/\$\{XRAY_VERSION\}/Xray-linux-\$\{XRAY_ARCH\}\.zip' "$DOCKERFILE" \
  "Xray download URL does not use the pinned version"
require_match 'sha256sum -c' "$DOCKERFILE" \
  "Xray archive checksum is not verified"
require_match 'org\.opencontainers\.image\.xray\.version=.*XRAY_VERSION' "$DOCKERFILE" \
  "final image does not expose the pinned Xray version"
if grep -Eq 'releases/latest|^FROM[[:space:]]+[^[:space:]@]+([[:space:]]+AS[[:space:]]+[^[:space:]]+)?$' "$DOCKERFILE"; then
  fail "production Dockerfile contains latest or a base image without a digest"
fi
require_match 'COPY --from=anytls-builder /out/anytls-client /usr/local/bin/anytls-client' "$DOCKERFILE" \
  "AnyTLS client is not included in the manager image"
require_match 'ENTRYPOINT \["/usr/local/bin/relay-sidecar-manager-entrypoint"\]' "$DOCKERFILE" \
  "production image does not use the asset-installing entrypoint"
require_match 'asset_target=.*SIDECAR_HOST_ROOT.*anytls-client' "$ENTRYPOINT" \
  "entrypoint does not target the mounted host asset directory"
require_match 'if \[ ! -e "\$asset_target" \]' "$ENTRYPOINT" \
  "entrypoint does not preserve an existing AnyTLS client"
require_match 'install .*anytls-client .*asset_target' "$ENTRYPOINT" \
  "entrypoint does not install the AnyTLS client into the mounted host asset directory"
require_match 'exec /usr/local/bin/anytls-sidecar-manager' "$ENTRYPOINT" \
  "entrypoint must always hand off to the manager"
require_match '^const alpineImage = "alpine:3\.20@sha256:[0-9a-f]{64}"$' "$MANAGER_SOURCE" \
  "sidecar Alpine image is not pinned to a manifest digest constant"
require_match 'docker\("run",.*alpineImage,' "$MANAGER_SOURCE" \
  "dynamic docker run does not use the pinned Alpine image constant"
require_match 'AnyTLS.*(failed|failure|unavailable|degraded).*(Trojan|Shadowsocks)|((Trojan|Shadowsocks).*){2}AnyTLS.*(failed|failure|unavailable|degraded)' "$ACCEPTANCE_DOC" \
  "acceptance documentation does not define the AnyTLS-only degraded health state"
pass "production AnyTLS installation assets are declared"

if [[ "${1:-}" == "--static-only" ]]; then
  exit 0
fi

command -v docker >/dev/null 2>&1 || fail "Docker is required for Compose validation"
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required"
DB_ROOT_PASSWORD=verify DB_PASSWORD=verify PPANEL_SECRET_KEY=verify \
  docker compose -f "$COMPOSE_FILE" config --quiet
pass "production Compose configuration is valid"
