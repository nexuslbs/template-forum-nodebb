#!/usr/bin/env bash
# Install and activate the plugins and themes declared in the manifest
# (config/plugins.json by default, or PLUGINS_MANIFEST from .env).
#   npm install <name>@<version> --save   (inside the NodeBB container)
#   ./nodebb activate <name>              (official verb)
#   ./nodebb build                        (official verb)
# CAVEAT: do NOT set plugins:active in config.json, or ./nodebb activate refuses
# with "Cannot activate plugins while plugin state configuration is set".
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd docker
require_cmd jq
load_env

manifest="${PLUGINS_MANIFEST:-$ROOT_DIR/config/plugins.json}"
[ -f "$manifest" ] || die "plugin manifest not found: $manifest"

mapfile -t pkgs < <(jq -r '((.plugins // [])[] | "\(.name)@\(.version)"), ((.themes // [])[] | "\(.name)@\(.version)")' "$manifest")
mapfile -t names < <(jq -r '((.plugins // [])[] | .name), ((.themes // [])[] | .name)' "$manifest")
[ "${#pkgs[@]}" -gt 0 ] || die "manifest $manifest declares no plugins or themes"

log "installing from $manifest: ${pkgs[*]}"
compose exec -T nodebb npm install --save "${pkgs[@]}"

for name in "${names[@]}"; do
  log "activating $name"
  compose exec -T nodebb ./nodebb activate "$name" --config=/opt/config/config.json
done

log "building assets"
compose exec -T nodebb ./nodebb build --config=/opt/config/config.json

log "active plugins on the running forum:"
compose exec -T nodebb ./nodebb plugins --config=/opt/config/config.json || true

log "apply: OK"
