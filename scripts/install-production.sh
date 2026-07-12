#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROD_DIR="$ROOT_DIR/docker-local/production"
ENV_FILE="$PROD_DIR/.env"
PPANEL_CONFIG="$PROD_DIR/ppanel.yaml"
NODE_CONFIG="$PROD_DIR/node.yml"

die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }

command -v docker >/dev/null 2>&1 || die "Docker is required"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required"
command -v curl >/dev/null 2>&1 || die "curl is required"
[[ "$(id -u)" -eq 0 ]] || die "Run this script as root"
[[ -f "$ROOT_DIR/backend/Dockerfile" ]] || die "backend directory is missing"
[[ -f "$ROOT_DIR/front/apps/admin/package.json" ]] || die "front directory is missing"
[[ -f "$ROOT_DIR/node/Dockerfile" ]] || die "node directory is missing"

random_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
  fi
}

if [[ ! -f "$ENV_FILE" ]]; then
  info "Creating $ENV_FILE"
  db_root_password="$(random_secret)"
  db_password="$(random_secret)"
  node_secret="$(random_secret)"
  cat > "$ENV_FILE" <<EOF
DB_ROOT_PASSWORD=$db_root_password
DB_PASSWORD=$db_password
PPANEL_SECRET_KEY=$node_secret
PPANEL_SERVER_ID=1
SIDECAR_POLL_SECONDS=30
EOF
  chmod 600 "$ENV_FILE"
else
  info "Using existing $ENV_FILE"
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

[[ -n "${DB_PASSWORD:-}" ]] || die "DB_PASSWORD is missing in $ENV_FILE"
[[ -n "${PPANEL_SECRET_KEY:-}" ]] || die "PPANEL_SECRET_KEY is missing in $ENV_FILE"

if grep -q '__DB_PASSWORD__' "$PPANEL_CONFIG"; then
  info "Rendering PPanel configuration"
  sed -i "s|__DB_PASSWORD__|$DB_PASSWORD|g; s|__NODE_SECRET__|$PPANEL_SECRET_KEY|g" "$PPANEL_CONFIG"
fi

if grep -q '__NODE_SECRET__' "$NODE_CONFIG"; then
  sed -i "s|__NODE_SECRET__|$PPANEL_SECRET_KEY|g" "$NODE_CONFIG"
fi

cd "$ROOT_DIR"
info "Validating Compose configuration"
docker compose -f "$PROD_DIR/docker-compose.yml" config >/dev/null

info "Building and starting PPanel, node and relay manager"
docker compose -f "$PROD_DIR/docker-compose.yml" up -d --build

info "Waiting for PPanel"
for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:18080/ >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl -fsS http://127.0.0.1:18080/ >/dev/null 2>&1 || die "PPanel did not become ready"

info "Installation completed"
echo "Admin web: http://127.0.0.1:13001"
echo "User web:  http://127.0.0.1:13000"
echo "PPanel API: http://127.0.0.1:18080"
echo "Check: docker compose -f $PROD_DIR/docker-compose.yml ps"
