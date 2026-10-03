#!/usr/bin/env bash
# Bring the NodeBB stack up and wait until BOTH services report healthy.
# On first run this creates .env from .env.example, generates throwaway secrets,
# and renders runtime/config/config.json from config/config.json.tpl.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd docker
ensure_env
render_config

# After `down --volumes` the nodebb-build volume is gone, but the persisted
# /opt/config/install_hash.md5 is not, so the image entrypoint would skip the
# asset build. Force it so the fresh forum serves fully built pages.
if ! docker volume inspect "${COMPOSE_PROJECT_NAME}_nodebb-build" >/dev/null 2>&1; then
  export START_BUILD=true
  log "build volume missing: forcing START_BUILD=true so assets are rebuilt"
fi

log "starting stack (project ${COMPOSE_PROJECT_NAME})"
compose up -d

log "waiting for mongo to become healthy"
wait_for_healthy mongo 60 || { compose logs --tail=50 mongo; die "mongo did not become healthy"; }

log "waiting for nodebb to become healthy"
wait_for_healthy nodebb 120 || { compose logs --tail=150 nodebb; die "nodebb did not become healthy"; }

compose ps
log "up: OK"
