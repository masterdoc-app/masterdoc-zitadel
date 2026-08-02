#!/usr/bin/env bash
# List (and optionally delete) humans in a Zitadel org.
#
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN
# Optional:
#   ORG_ID (default: Fixaverse Demo 382715225649971203)
#   DELETE_USER_IDS — space-separated user ids to delete
#   DELETE_EMAILS — space-separated emails to delete (resolved in org)
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
ORG_ID="${ORG_ID:-382715225649971203}"
API="https://${DOMAIN}"

mgmt_curl() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -X "$method" "${API}${path}" "$@"
}

echo "==> Org ${ORG_ID} users"
CODE="$(mgmt_curl POST /management/v1/users/_search \
  -d '{"query":{"offset":0,"limit":100,"asc":true}}')"
[[ "$CODE" == "200" ]] || {
  echo "List users failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
}

python3 - <<'PY'
import json
body = json.load(open("/tmp/zitadel-body.json"))
rows = body.get("result") or []
print(f"TOTAL={len(rows)} (reported={body.get('details',{}).get('totalResult')})")
for u in rows:
    human = u.get("human") or {}
    profile = human.get("profile") or {}
    email = (human.get("email") or {}).get("email") or u.get("email") or ""
    gn = profile.get("firstName") or profile.get("givenName") or ""
    fn = profile.get("lastName") or profile.get("familyName") or ""
    print(f"USER id={u.get('id')} email={email} name={gn} {fn} state={u.get('state')} type={u.get('userName') or u.get('type')}")
PY

if [[ -n "${DELETE_EMAILS:-}" ]]; then
  echo "==> Resolve DELETE_EMAILS"
  for email in $DELETE_EMAILS; do
    CODE="$(mgmt_curl POST /management/v1/users/_search -d "$(EMAIL="$email" python3 -c '
import json,os
print(json.dumps({
  "query":{"offset":0,"limit":20,"asc":True},
  "queries":[{"emailQuery":{"emailAddress":os.environ["EMAIL"],"method":"TEXT_QUERY_METHOD_EQUALS"}}]
}))
')")"
    [[ "$CODE" == "200" ]] || continue
    uid="$(python3 -c 'import json; r=json.load(open("/tmp/zitadel-body.json")).get("result") or []; print(r[0]["id"] if r else "")')"
    if [[ -n "$uid" ]]; then
      DELETE_USER_IDS="${DELETE_USER_IDS:-} $uid"
      echo "email=$email -> id=$uid"
    else
      echo "email=$email -> not found"
    fi
  done
fi

if [[ -n "${DELETE_USER_IDS:-}" ]]; then
  echo "==> Delete users"
  for uid in $DELETE_USER_IDS; do
    CODE="$(mgmt_curl DELETE "/management/v1/users/${uid}")"
    if [[ "$CODE" == "200" || "$CODE" == "204" ]]; then
      echo "DELETED=$uid"
    else
      echo "DELETE_FAILED id=$uid code=$CODE body=$(cat /tmp/zitadel-body.json)" >&2
      exit 1
    fi
  done
  echo "==> Users after delete"
  CODE="$(mgmt_curl POST /management/v1/users/_search \
    -d '{"query":{"offset":0,"limit":100,"asc":true}}')"
  python3 - <<'PY'
import json
rows = json.load(open("/tmp/zitadel-body.json")).get("result") or []
print(f"TOTAL={len(rows)}")
for u in rows:
    human = u.get("human") or {}
    profile = human.get("profile") or {}
    email = (human.get("email") or {}).get("email") or ""
    gn = profile.get("firstName") or ""
    fn = profile.get("lastName") or ""
    print(f"USER id={u.get('id')} email={email} name={gn} {fn} state={u.get('state')}")
PY
fi
