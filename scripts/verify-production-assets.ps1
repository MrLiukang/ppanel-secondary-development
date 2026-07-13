$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent $PSScriptRoot
$Dockerfile = Join-Path $RootDir 'docker-local/production/anytls-sidecar-manager.Dockerfile'
$Entrypoint = Join-Path $RootDir 'scripts/relay-sidecar-manager-entrypoint.sh'
$ComposeFile = Join-Path $RootDir 'docker-local/production/docker-compose.yml'
$PanelConfig = Join-Path $RootDir 'docker-local/production/ppanel.yaml'
$AcceptanceDoc = Join-Path $RootDir 'docs/PRODUCTION_RELAY_ACCEPTANCE.md'
$ManagerSource = Join-Path $RootDir 'backend/tools/anytls-sidecar-manager/main.go'

function Require-Match([string]$Pattern, [string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "[FAIL] Missing file: $Path" }
    if ((Get-Content -Raw -LiteralPath $Path) -notmatch $Pattern) { throw "[FAIL] $Description" }
}

Require-Match '(?m)^ARG ANYTLS_COMMIT=[0-9a-f]{40}$' $Dockerfile 'AnyTLS source is not pinned to an immutable commit'
Require-Match 'https://github\.com/anytls/anytls-go\.git' $Dockerfile 'AnyTLS client source is not the official repository'
Require-Match 'git checkout .*\$\{ANYTLS_COMMIT\}' $Dockerfile 'AnyTLS source checkout does not use the declared commit'
Require-Match 'git rev-parse HEAD.*ANYTLS_COMMIT|ANYTLS_COMMIT.*git rev-parse HEAD' $Dockerfile 'AnyTLS build does not verify the checked-out commit'
Require-Match 'org\.opencontainers\.image\.anytls\.commit=.*ANYTLS_COMMIT' $Dockerfile 'Final image does not expose the verified AnyTLS commit'
Require-Match 'go build .*\./cmd/client' $Dockerfile 'AnyTLS client package is not built into the image asset'
Require-Match '(?m)^ARG XRAY_VERSION=v\d+\.\d+\.\d+$' $Dockerfile 'Xray version is not pinned'
Require-Match '(?m)^ARG XRAY_SHA256_AMD64=[0-9a-f]{64}$' $Dockerfile 'Xray amd64 SHA256 is not pinned'
Require-Match '(?m)^ARG XRAY_SHA256_ARM64=[0-9a-f]{64}$' $Dockerfile 'Xray arm64 SHA256 is not pinned'
Require-Match 'releases/download/\$\{XRAY_VERSION\}/Xray-linux-\$\{XRAY_ARCH\}\.zip' $Dockerfile 'Xray download URL does not use the pinned version'
Require-Match 'sha256sum -c' $Dockerfile 'Xray archive checksum is not verified'
Require-Match 'org\.opencontainers\.image\.xray\.version=.*XRAY_VERSION' $Dockerfile 'Final image does not expose the pinned Xray version'
Require-Match '(?m)^ARG X_NET_VERSION=v\d+\.\d+\.\d+$' $Dockerfile 'sidecar manager x/net dependency is not pinned'
Require-Match 'go get golang\.org/x/net@\$\{X_NET_VERSION\}' $Dockerfile 'sidecar manager build does not use the pinned x/net version'
$DockerfileText = Get-Content -Raw -LiteralPath $Dockerfile
if ($DockerfileText -match 'releases/latest|go mod tidy|(?m)^FROM\s+[^\s@]+(?:\s+AS\s+\S+)?$') {
    throw '[FAIL] production Dockerfile contains latest or a base image without a digest'
}
Require-Match 'COPY --from=anytls-builder /out/anytls-client /usr/local/bin/anytls-client' $Dockerfile 'AnyTLS client is not included in the manager image'
Require-Match 'ENTRYPOINT \["/usr/local/bin/relay-sidecar-manager-entrypoint"\]' $Dockerfile 'production image does not use the asset-installing entrypoint'
Require-Match 'asset_target=.*SIDECAR_HOST_ROOT.*anytls-client' $Entrypoint 'entrypoint does not target the mounted host asset directory'
Require-Match 'if \[ ! -e "\$asset_target" \]' $Entrypoint 'entrypoint does not preserve an existing AnyTLS client'
Require-Match 'install .*anytls-client .*asset_target' $Entrypoint 'entrypoint does not install the AnyTLS client into the mounted host asset directory'
Require-Match 'exec /usr/local/bin/anytls-sidecar-manager' $Entrypoint 'entrypoint must always hand off to the manager'
Require-Match '(?m)^const alpineImage = "alpine:3\.20@sha256:[0-9a-f]{64}"$' $ManagerSource 'sidecar Alpine image is not pinned to a manifest digest constant'
Require-Match 'docker\("run",.*alpineImage,' $ManagerSource 'dynamic docker run does not use the pinned Alpine image constant'
Require-Match '(?m)^\s*AllowLegacyNodeSecret:\s*false\s*$' $PanelConfig 'production panel config must reject the legacy global node secret'
Require-Match 'AnyTLS.*(failed|failure|unavailable|degraded).*(Trojan|Shadowsocks)|((Trojan|Shadowsocks).*){2}AnyTLS.*(failed|failure|unavailable|degraded)' $AcceptanceDoc 'Acceptance documentation does not define the AnyTLS-only degraded health state'
Write-Host '[PASS] production AnyTLS installation assets are declared'

if ($args -contains '--static-only') { exit 0 }

$env:DB_ROOT_PASSWORD = 'verify'
$env:DB_PASSWORD = 'verify'
$env:PPANEL_SECRET_KEY = 'verify'
docker compose -f $ComposeFile config --quiet
if ($LASTEXITCODE -ne 0) { throw '[FAIL] production Compose configuration is invalid' }
Write-Host '[PASS] production Compose configuration is valid'
