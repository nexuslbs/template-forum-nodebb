#!/usr/bin/env bash
# Shared helpers for the lifecycle scripts. This file is SOURCED, never run.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/docker-compose.yml}"
RUNTIME_DIR="${RUNTIME_DIR:-$ROOT_DIR/runtime}"
API_BODY_FILE="$RUNTIME_DIR/api-last-response.json"
API_CODE=""

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

load_env() {
  [ -f "$ENV_FILE" ] || die "missing $ENV_FILE (run: cp .env.example .env, or just run scripts/up.sh)"
  # Parse .env line by line instead of `source`-ing it: values may contain
  # characters `source` would try to interpret. One layer of surrounding quotes
  # is stripped, so both `K=v w` and `K="v w"` work.
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in *=*) : ;; *) continue ;; esac
    key="${line%%=*}"
    val="${line#*=}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
    export "$key=$val"
  done < "$ENV_FILE"
  # The operator's shell may already define COMPOSE_PROJECT_NAME (this host
  # exports omni-stack for production). The .env value must win, so it is
  # re-exported here and pinned with -p in compose().
  COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-template-forum-nodebb}"
  export COMPOSE_PROJECT_NAME
}

# Rewrite one KEY=value line in .env. Generated values are base64 (A-Za-z0-9+/=)
# which contains none of the sed metacharacters, so `|` is a safe delimiter.
set_env_var() {
  local key="$1" value="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

# Create .env from .env.example on first run and replace every placeholder
# secret with an `openssl rand -base64 24` local throwaway value. Real values
# are never committed: .env is gitignored.
ensure_env() {
  require_cmd openssl
  if [ ! -f "$ENV_FILE" ]; then
    cp "$ROOT_DIR/.env.example" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    log "created $ENV_FILE from .env.example"
  fi
  load_env
  local key val
  for key in NODEBB_DB_PASSWORD NODEBB_SECRET NODEBB_ADMIN_PASSWORD; do
    val="${!key:-}"
    case "$val" in
      ""|change-me*|CHANGE_ME*)
        val="$(openssl rand -base64 24)"
        set_env_var "$key" "$val"
        export "$key=$val"
        log "generated local throwaway value for $key (written to .env, gitignored)"
        ;;
    esac
  done
}

# Every compose call is pinned to this stack's project name. Never run a bare
# `docker compose` in this directory: on a host that exports COMPOSE_PROJECT_NAME
# for a DIFFERENT project, a bare call targets that project instead. The guard
# below refuses the production project name outright.
compose() {
  [ "${COMPOSE_PROJECT_NAME:-}" != "omni-stack" ] \
    || die "refusing to run compose against the protected omni-stack project"
  docker compose --project-name "$COMPOSE_PROJECT_NAME" \
    --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

stack_url() {
  local u="${NODEBB_URL:?NODEBB_URL is not set in $ENV_FILE}"
  printf '%s' "${u%/}"
}

# Substitute every __NODEBB_*__ placeholder in a template with the .env values.
# jq does the substitution so every value is JSON-escaped (safe inside both a
# JSON string and a JavaScript string literal).
render_template() {
  local tpl="$1" out="$2"
  [ -f "$tpl" ] || die "template not found: $tpl"
  jq -n -r \
    --rawfile tpl "$tpl" \
    --arg url "${NODEBB_URL:?}" \
    --arg secret "${NODEBB_SECRET:?}" \
    --arg host "${NODEBB_DB_HOST:-mongo}" \
    --arg port "${NODEBB_DB_PORT:-27017}" \
    --arg user "${NODEBB_DB_USER:-nodebb}" \
    --arg pass "${NODEBB_DB_PASSWORD:?}" \
    --arg name "${NODEBB_DB_NAME:-nodebb}" \
    '$tpl
      | gsub("__NODEBB_URL__"; ($url | @json | .[1:-1]))
      | gsub("__NODEBB_SECRET__"; ($secret | @json | .[1:-1]))
      | gsub("__NODEBB_DB_HOST__"; ($host | @json | .[1:-1]))
      | gsub("__NODEBB_DB_PORT__"; $port)
      | gsub("__NODEBB_DB_USER__"; ($user | @json | .[1:-1]))
      | gsub("__NODEBB_DB_PASSWORD__"; ($pass | @json | .[1:-1]))
      | gsub("__NODEBB_DB_NAME__"; ($name | @json | .[1:-1]))
    ' > "$out"
}

# Render config/config.json.tpl plus the mongo user-init template into runtime/.
render_config() {
  require_cmd jq
  local tpl="${CONFIG_TEMPLATE:-$ROOT_DIR/config/config.json.tpl}"
  mkdir -p "$RUNTIME_DIR/config"
  render_template "$tpl" "$RUNTIME_DIR/config/config.json"
  # The NodeBB image runs as uid 1001 and must write config.json, package.json
  # and install_hash.md5 into /opt/config. Make the bind-mounted dir writable.
  if [ "$(id -u)" = "0" ]; then
    chown -R 1001:1001 "$RUNTIME_DIR/config" 2>/dev/null || true
  fi
  chmod 0770 "$RUNTIME_DIR/config"
  chmod 0660 "$RUNTIME_DIR/config/config.json"
  log "rendered $RUNTIME_DIR/config/config.json from $tpl"

  if [ "${NODEBB_DB:-mongo}" = "mongo" ]; then
    mkdir -p "$RUNTIME_DIR/mongo"
    render_template "$ROOT_DIR/config/mongodb-user-init.js.tpl" \
      "$RUNTIME_DIR/mongo/mongodb-user-init.js"
    chmod 0755 "$RUNTIME_DIR/mongo"
    chmod 0644 "$RUNTIME_DIR/mongo/mongodb-user-init.js"
    log "rendered $RUNTIME_DIR/mongo/mongodb-user-init.js"
  fi
}

wait_for_healthy() {
  local service="$1" tries="${2:-60}" i=1 status
  while [ "$i" -le "$tries" ]; do
    status="$(compose ps --format '{{.Health}}' "$service" 2>/dev/null | head -n1 || true)"
    [ "$status" = "healthy" ] && return 0
    sleep 5
    i=$((i + 1))
  done
  return 1
}

# Mint a NodeBB MASTER API token non-interactively:
#   GET  /api/config              -> csrf_token + session cookie
#   POST /api/v3/utilities/login  -> admin session (x-csrf-token)
#   POST /api/v3/admin/tokens     -> master token (uid:0 + password re-auth)
# The token is written to runtime/api-token.json (mode 600, gitignored) along
# with the admin uid used as `_uid` on every master-token call.
mint_master_token() {
  require_cmd curl
  require_cmd jq
  local url jar body csrf code uid token
  url="$(stack_url)"
  mkdir -p "$RUNTIME_DIR"
  jar="$(mktemp)"
  body="$(mktemp)"

  curl -fsS -c "$jar" -o "$body" "$url/api/config"
  csrf="$(jq -r '.csrf_token // empty' "$body")"
  [ -n "$csrf" ] || { cat "$body"; die "GET /api/config did not return csrf_token"; }

  code="$(curl -sS -b "$jar" -c "$jar" -o "$body" -w '%{http_code}' \
    -X POST "$url/api/v3/utilities/login" \
    -H "x-csrf-token: $csrf" -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg u "$NODEBB_ADMIN_USERNAME" --arg p "$NODEBB_ADMIN_PASSWORD" --arg k password \
              '{username:$u, ($k):$p}')")"
  [ "$code" = "200" ] || { cat "$body"; die "login returned HTTP $code"; }
  uid="$(jq -r '.response.uid // empty' "$body")"
  [ -n "$uid" ] || { cat "$body"; die "login response carried no uid"; }

  # A fresh /api/config on the logged-in session yields the session csrf token.
  curl -fsS -b "$jar" -c "$jar" -o "$body" "$url/api/config"
  csrf="$(jq -r '.csrf_token // empty' "$body")"
  [ -n "$csrf" ] || die "GET /api/config after login did not return csrf_token"

  code="$(curl -sS -b "$jar" -c "$jar" -o "$body" -w '%{http_code}' \
    -X POST "$url/api/v3/admin/tokens" \
    -H "x-csrf-token: $csrf" -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg p "$NODEBB_ADMIN_PASSWORD" --arg k password \
              '{uid:0,description:"template-forum-nodebb",($k):$p}')")"
  [ "$code" = "200" ] || { cat "$body"; die "POST /api/v3/admin/tokens returned HTTP $code"; }
  token="$(jq -r '.response.secret // empty' "$body")"
  [ -n "$token" ] || { cat "$body"; die "admin/tokens response carried no response.secret"; }

  umask 077
  jq -n --arg uid "$uid" --arg token "$token" '{uid:$uid,token:$token}' \
    > "$RUNTIME_DIR/api-token.json"
  chmod 600 "$RUNTIME_DIR/api-token.json"
  log "minted master token for admin uid=$uid (secret in $RUNTIME_DIR/api-token.json, mode 600)"
}

# api METHOD PATH [JSON] -> prints nothing; sets API_CODE and writes the body to
# API_BODY_FILE. The master token requires `_uid` on every call.
api() {
  local method="$1" path="$2" data="${3:-}" url token uid sep
  # Resolve from the CURRENT RUNTIME_DIR: load_env can override it after
  # lib.sh is sourced (a derived instance sets its own RUNTIME_DIR in .env),
  # so the top-level assignment would otherwise point at the repo runtime/.
  API_BODY_FILE="$RUNTIME_DIR/api-last-response.json"
  require_cmd curl
  require_cmd jq
  url="$(stack_url)"
  [ -f "$RUNTIME_DIR/api-token.json" ] || die "no API token; run scripts/verify.sh"
  token="$(jq -r '.token' "$RUNTIME_DIR/api-token.json")"
  uid="$(jq -r '.uid' "$RUNTIME_DIR/api-token.json")"
  sep='?'
  case "$path" in *\?*) sep='&' ;; esac
  path="${path}${sep}_uid=${uid}"
  local args=(-sS -X "$method" "$url$path"
    -H "Authorization: Bearer $token" -o "$API_BODY_FILE" -w '%{http_code}')
  if [ -n "$data" ]; then
    args+=(-H 'Content-Type: application/json' --data "$data")
  fi
  API_CODE="$(curl "${args[@]}")"
}
