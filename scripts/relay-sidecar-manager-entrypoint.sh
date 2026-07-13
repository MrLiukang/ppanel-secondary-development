#!/bin/sh

asset_target="${SIDECAR_HOST_ROOT%/}/anytls-client"
if [ ! -e "$asset_target" ]; then
  if install -m 0755 /usr/local/bin/anytls-client "$asset_target"; then
    echo "installed AnyTLS client at $asset_target"
  else
    echo "warning: AnyTLS asset installation failed at $asset_target; AnyTLS health is degraded, but Trojan and Shadowsocks runtimes will continue" >&2
  fi
else
  echo "preserving existing AnyTLS client at $asset_target"
fi

exec /usr/local/bin/anytls-sidecar-manager
