#!/usr/bin/env bash
# One-call deploy entrypoint for this NodeBB template.
#
#   scripts/deploy.sh <user@host> [--dry-run] [--dest DIR]
#   scripts/deploy.sh --local      [--dry-run]
#
# It presupposes ONLY an SSH-reachable machine with `docker` (and `git`/`rsync`
# for the remote leg) and, on the remote, a repo checkout with a filled `.env`
# (the remote scripts create one from `.env.example` when it is absent). The
# remote leg rsyncs the repo, then runs the same local leg there. The local leg
# composes the repo's EXISTING scripts and does not reimplement them:
#
#   scripts/up.sh         # env + render + compose up + wait healthy
#   scripts/bootstrap.sh  # official SETUP=1 env-path ./nodebb setup (first run only)
#   scripts/apply.sh      # manifest plugins/themes (npm install + ./nodebb activate)
#   scripts/verify.sh     # end-to-end API gate
#
# Non-interactive: ssh uses BatchMode=yes, so it never prompts. Idempotent: the
# install state is read from the running database, so a re-run skips setup and
# just re-applies the manifest and re-runs the gate. `--dry-run` prints the
# exact sequence and touches nothing (it never creates `.env`).
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
usage: scripts/deploy.sh [--local | <user@host>] [--dry-run] [--dest DIR]

  <user@host>   remote target (ssh + rsync + docker on the remote host)
  --local       deploy on this host
  --dry-run     print the exact command sequence and exit without changing anything
  --dest DIR    remote directory to sync into (default: /opt/template-forum-nodebb)
EOF
}

MODE=""
HOST=""
DRY_RUN=0
DEST=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --local|local) MODE=local ;;
    --dry-run) DRY_RUN=1 ;;
    --dest) shift; DEST="${1:-}" ;;
    --dest=*) DEST="${1#*=}" ;;
    -h|--help) usage; exit 0 ;;
    --*) die "unknown flag: $1 (see --help)" ;;
    *) [ -z "$HOST" ] || die "unexpected extra argument: $1"; HOST="$1" ;;
  esac
  shift
done

if [ -z "$MODE" ]; then
  if [ -n "$HOST" ]; then MODE=remote; else usage; die "no target: pass --local or <user@host>"; fi
fi
[ "$MODE" = remote ] && [ -z "$HOST" ] && die "remote mode needs <user@host>"

if [ "$DRY_RUN" = 1 ]; then
  # Read-only: fall back to .env.example so a dry run creates nothing.
  if [ ! -f "$ENV_FILE" ]; then
    ENV_FILE="$ROOT_DIR/.env.example"
    log "note: .env absent; --dry-run reads .env.example and writes nothing"
  fi
  load_env
fi

stack_url() {
  local bind="${NODEBB_BIND_ADDR:-127.0.0.1}"
  case "$bind" in ""|0.0.0.0|\*) bind="localhost" ;; esac
  printf 'http://%s:%s' "$bind" "${NODEBB_PORT:-4567}"
}

# True when the forum database already holds data (setup has run). Reads the
# running mongo container; used to make the deploy idempotent.
nodebb_installed() {
  local count
  count="$(compose exec -T -e DBNAME="${NODEBB_DB_NAME:-nodebb}" mongo sh -c \
    'mongosh --quiet --host 127.0.0.1 --username "$MONGO_INITDB_ROOT_USERNAME" \
       --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin \
       --eval "db.getSiblingDB(\"$DBNAME\").getCollectionNames().length"' 2>/dev/null \
    | tail -n1 | tr -dc '0-9')"
  log "mongo collections in ${NODEBB_DB_NAME:-nodebb}: ${count:-0}"
  [ "${count:-0}" -gt 0 ]
}

run_local() {
  if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY-RUN (local):\n'
    printf '  scripts/up.sh\n'
    printf '  scripts/bootstrap.sh   # official SETUP=1 ./nodebb setup (only when the database is empty)\n'
    printf '  scripts/apply.sh       # npm install + ./nodebb activate + ./nodebb build\n'
    printf '  scripts/verify.sh\n'
    printf '  url: %s\n' "$(stack_url)"
    return 0
  fi

  require_cmd docker
  ensure_env
  log "deploy(local): start + install + apply + verify"
  "$SCRIPT_DIR/up.sh"
  if nodebb_installed; then
    log "deploy(local): database already installed; skipping scripts/bootstrap.sh"
  else
    "$SCRIPT_DIR/bootstrap.sh"
  fi
  "$SCRIPT_DIR/apply.sh"
  "$SCRIPT_DIR/verify.sh"
  log "deploy(local): OK -> $(stack_url)"
}

run_remote() {
  local dest="${DEST:-/opt/template-forum-nodebb}"
  local ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
  # Never ship the real .env, local backups/runtime state or the host overlay.
  local rsync_opts=(-az --exclude .git --exclude .env --exclude backups --exclude runtime
                    --exclude docker-compose.override.yml --exclude '*.tar.gz' --exclude '*.sql')
  local remote_cmd="cd '$dest' && scripts/deploy.sh --local"

  if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY-RUN (remote %s):\n' "$HOST"
    printf '  rsync %s %s/ %s:%s/\n' "${rsync_opts[*]}" "$ROOT_DIR" "$HOST" "$dest"
    printf '  ssh %s %s "%s"\n' "${ssh_opts[*]}" "$HOST" "$remote_cmd"
    printf '  note: .env is NOT synced; the remote scripts create it from .env.example when absent\n'
    printf '  url: %s   (on the remote host)\n' "$(stack_url)"
    return 0
  fi

  require_cmd ssh
  require_cmd rsync
  log "deploy(remote $HOST): sync -> up -> bootstrap -> apply -> verify"
  rsync "${rsync_opts[@]}" "$ROOT_DIR/" "$HOST:$dest/"
  ssh "${ssh_opts[@]}" "$HOST" "$remote_cmd"
  log "deploy(remote): OK -> $(stack_url) on $HOST"
}

if [ "$MODE" = local ]; then
  run_local
else
  run_remote
fi
