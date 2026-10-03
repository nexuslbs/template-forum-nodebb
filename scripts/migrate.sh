#!/usr/bin/env bash
# Run the official NodeBB upgrade routine on the running image.
#
# NodeBB's official upgrade path (docs configuring/upgrade.md) is: stop, back up,
# swap to the new tag, run `./nodebb upgrade`, start. In Docker you bump
# NODEBB_IMAGE_TAG in .env, `compose up -d` recreates the container, and the
# image entrypoint runs `./nodebb upgrade` automatically when the image's
# install/package.json hash differs from /opt/config/install_hash.md5. This
# script makes the `./nodebb upgrade` step explicit and idempotent.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd docker
load_env

log "ensuring mongo is healthy"
compose up -d mongo
wait_for_healthy mongo 60 || { compose logs --tail=50 mongo; die "mongo did not become healthy"; }

log "official ./nodebb upgrade (package update, dependency/plugin upgrades, schema migrations, asset build)"
compose exec -T nodebb ./nodebb upgrade --config=/opt/config/config.json

log "recreating nodebb on the pinned image"
compose up -d --force-recreate nodebb
wait_for_healthy nodebb 180 || { compose logs --tail=200 nodebb; die "nodebb did not become healthy after upgrade"; }

compose ps
log "migrate: OK"
