#!/usr/bin/env bash
# Restore a backup produced by scripts/backup.sh.
#   usage: restore.sh <backup-dir | newest>
# The mongo service must be up before the dump can be imported, so this script
# brings the stack up and waits for health first. That makes restore work after
# `down` (volumes kept) and after `down --volumes` (empty volumes).
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd docker
load_env

arg="${1:-newest}"
if [ "$arg" = "newest" ]; then
  dir="$(ls -1d "$ROOT_DIR"/backups/*/ 2>/dev/null | sort | tail -n1 || true)"
  [ -n "$dir" ] || die "no backup directories under $ROOT_DIR/backups"
else
  dir="$arg"
fi
dir="${dir%/}"

[ -f "$dir/nodebb.archive" ] || die "missing $dir/nodebb.archive"
[ -f "$dir/uploads.tar.gz" ] || die "missing $dir/uploads.tar.gz"

log "ensuring mongo is up and healthy (restore needs a running database)"
compose up -d mongo
wait_for_healthy mongo 60 || { compose logs --tail=50 mongo; die "mongo did not become healthy"; }

log "ensuring nodebb is up (exec target for the uploads tar and the rebuild)"
compose up -d nodebb
wait_for_healthy nodebb 180 || { compose logs --tail=200 nodebb; die "nodebb did not become healthy"; }

log "restoring from $dir"
log "1/3 restoring database (mongorestore --drop --archive)"
compose exec -T mongo sh -c \
  'exec mongorestore --username "$MONGO_INITDB_ROOT_USERNAME" --password "$MONGO_INITDB_ROOT_PASSWORD" \
     --authenticationDatabase admin --drop --archive' \
  < "$dir/nodebb.archive"

log "2/3 restoring uploads"
compose exec -T nodebb sh -c \
  'mkdir -p /usr/src/app/public/uploads && tar xzf - -C /usr/src/app/public/uploads' \
  < "$dir/uploads.tar.gz"

log "3/3 rebuilding assets (the build volume may have been recreated)"
compose exec -T nodebb ./nodebb build --config=/opt/config/config.json

log "recreating nodebb so it reconnects to the restored database"
compose up -d --force-recreate nodebb
wait_for_healthy nodebb 180 || { compose logs --tail=200 nodebb; die "nodebb did not become healthy after restore"; }

compose ps
log "restore: OK"
