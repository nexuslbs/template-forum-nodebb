#!/usr/bin/env bash
# Backup the two stateful pieces plus the rendered config, following the
# official upgrade guide's data-safety procedure:
#   - mongodump of the nodebb database (the official docs document `mongodump`
#     for MongoDB; NodeBB has NO backup CLI and NO ACP backup route in core)
#   - tar of /usr/src/app/public/uploads
#   - the rendered /opt/config/config.json
# Output lands in backups/<UTC timestamp>/ (gitignored: it holds credentials).
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd docker
load_env

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
dir="$ROOT_DIR/backups/$stamp"
mkdir -p "$dir"

log "1/3 mongodump -> $dir/nodebb.archive"
compose exec -T mongo sh -c \
  'exec mongodump --username "$MONGO_INITDB_ROOT_USERNAME" --password "$MONGO_INITDB_ROOT_PASSWORD" \
     --authenticationDatabase admin --db "$MONGO_INITDB_DATABASE" --archive' \
  > "$dir/nodebb.archive"

log "2/3 uploads tar -> $dir/uploads.tar.gz"
compose exec -T nodebb tar czf - -C /usr/src/app/public/uploads . > "$dir/uploads.tar.gz"

log "3/3 rendered config -> $dir/config.json"
cp "$RUNTIME_DIR/config/config.json" "$dir/config.json"

( cd "$dir" && sha256sum nodebb.archive uploads.tar.gz config.json > SHA256SUMS )
log "wrote $(du -h "$dir" | awk '{print $1}') to $dir"
ls -l "$dir"
log "backup: OK"
