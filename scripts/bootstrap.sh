#!/usr/bin/env bash
# Non-interactive provision of a fresh forum:
#   1) mongo up and healthy
#   2) OFFICIAL env-path setup, run as a one-off because setup calls
#      process.exit(): SETUP=1 + the NODEBB_* map from src/install.js, which the
#      image entrypoint turns into `./nodebb setup --config=/opt/config/config.json`
#   3) start NodeBB against the installed database
#   4) ./nodebb build
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd docker
ensure_env
render_config

log "1/4 ensuring mongo is healthy"
compose up -d mongo
wait_for_healthy mongo 60 || { compose logs --tail=50 mongo; die "mongo did not become healthy"; }

log "2/4 non-interactive setup (SETUP=1, official NODEBB_* env map)"
compose run --rm -e SETUP=1 nodebb

log "3/4 starting NodeBB against the installed database"
compose up -d --force-recreate nodebb
wait_for_healthy nodebb 180 || { compose logs --tail=200 nodebb; die "nodebb did not become healthy after setup"; }

log "4/4 ./nodebb build"
compose exec -T nodebb ./nodebb build --config=/opt/config/config.json

compose ps
log "bootstrap: OK"
