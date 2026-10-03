#!/usr/bin/env bash
# End-to-end verification with the OFFICIAL write API:
#   1) HTTP health
#   2) mint a master API token non-interactively
#   3) POST a category
#   4) POST a topic
#   5) reply with POST /api/v3/topics/:tid (there is NO POST /api/v3/posts)
#   6) curl the public topic URL and require HTTP 200
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd curl
require_cmd jq
ensure_env
mkdir -p "$RUNTIME_DIR"
url="$(stack_url)"

log "1/6 HTTP health: GET $url/api/config"
code="$(curl -sS -o "$RUNTIME_DIR/api-config.json" -w '%{http_code}' "$url/api/config")"
printf 'HTTP %s\n' "$code"
jq '{version: .version, uid: .uid, loggedIn: .loggedIn}' "$RUNTIME_DIR/api-config.json" 2>/dev/null || cat "$RUNTIME_DIR/api-config.json"
[ "$code" = "200" ] || die "GET /api/config returned HTTP $code"

log "2/6 minting master API token (GET /api/config, POST utilities/login, POST admin/tokens)"
mint_master_token

stamp="$(date -u +%Y%m%dT%H%M%SZ)"

log "3/6 POST /api/v3/categories"
api POST /api/v3/categories \
  "$(jq -nc --arg n "Template Category $stamp" '{name:$n,description:"Created by scripts/verify.sh"}')"
printf 'HTTP %s\n' "$API_CODE"
jq '{status: .status, cid: .response.cid, name: .response.name}' "$API_BODY_FILE" 2>/dev/null || cat "$API_BODY_FILE"
[ "$API_CODE" = "200" ] || die "create category returned HTTP $API_CODE"
cid="$(jq -r '.response.cid // empty' "$API_BODY_FILE")"
[ -n "$cid" ] || die "category response carried no cid"

log "4/6 POST /api/v3/topics"
api POST /api/v3/topics \
  "$(jq -nc --argjson cid "$cid" --arg t "Template smoke topic $stamp" \
        '{cid:$cid,title:$t,content:"Template smoke topic body."}')"
printf 'HTTP %s\n' "$API_CODE"
jq '{status: .status, tid: (.response.tid // .response.topicData.tid), slug: (.response.slug // .response.topicData.slug)}' "$API_BODY_FILE" 2>/dev/null || cat "$API_BODY_FILE"
[ "$API_CODE" = "200" ] || die "create topic returned HTTP $API_CODE"
tid="$(jq -r '.response.tid // .response.topicData.tid // .response.postData.tid // empty' "$API_BODY_FILE")"
slug="$(jq -r '.response.slug // .response.topicData.slug // empty' "$API_BODY_FILE")"
[ -n "$tid" ] || die "topic response carried no tid"

log "5/6 POST /api/v3/topics/$tid (reply; POST /api/v3/posts does not exist)"
api POST "/api/v3/topics/$tid" "$(jq -nc '{content:"Template smoke reply."}')"
printf 'HTTP %s\n' "$API_CODE"
jq '{status: .status, pid: (.response.pid // .response.postData.pid)}' "$API_BODY_FILE" 2>/dev/null || cat "$API_BODY_FILE"
[ "$API_CODE" = "200" ] || die "reply returned HTTP $API_CODE"

log "6/6 GET the public topic URL"
topic_url="$url/topic/$tid"
if [ -n "$slug" ]; then topic_url="$url/topic/$slug"; fi
code="$(curl -sS -o /dev/null -w '%{http_code}' "$topic_url")"
printf 'GET %s -> HTTP %s\n' "$topic_url" "$code"
if [ "$code" != "200" ] && [ -n "$slug" ]; then
  topic_url="$url/topic/$tid"
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$topic_url")"
  printf 'GET %s -> HTTP %s\n' "$topic_url" "$code"
fi
[ "$code" = "200" ] || die "public topic URL did not return HTTP 200 (got $code)"

log "verify: OK (category $cid, topic $tid)"
