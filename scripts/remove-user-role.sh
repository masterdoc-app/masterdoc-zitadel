#!/usr/bin/env bash
# Remove one project role key from a human's grant in a client org.
#
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN, ZITADEL_ORG_ID (platform org)
#           TARGET_ORG_ID, TARGET_EMAIL, REMOVE_ROLE
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
PLATFORM_ORG_ID="${ZITADEL_ORG_ID:?}"
TARGET_ORG_ID="${TARGET_ORG_ID:?}"
TARGET_EMAIL="${TARGET_EMAIL:?}"
REMOVE_ROLE="${REMOVE_ROLE:?}"
PROJECT_NAME="${PROJECT_NAME:-masterdoc-toir}"
API="https://${DOMAIN}"

mgmt_curl() {
  local org_id="$1" method="$2" path="$3"
  shift 3
  curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${org_id}" \
    -X "$method" "${API}${path}" "$@"
}

echo "==> Project ${PROJECT_NAME} (platform org)"
CODE="$(mgmt_curl "$PLATFORM_ORG_ID" POST /management/v1/projects/_search \
  -d '{"query":{"offset":0,"limit":100,"asc":true}}')"
[[ "$CODE" == "200" ]] || {
  echo "List projects failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
}
PROJECT_ID="$(PROJECT_NAME="$PROJECT_NAME" python3 - <<'PY'
import json, os
name = os.environ["PROJECT_NAME"]
for p in json.load(open("/tmp/zitadel-body.json")).get("result") or []:
    if p.get("name") == name:
        print(p["id"])
        break
PY
)"
[[ -n "$PROJECT_ID" ]] || {
  echo "Project ${PROJECT_NAME} not found" >&2
  exit 1
}
echo "PROJECT_ID=$PROJECT_ID"

echo "==> Find user ${TARGET_EMAIL} in org ${TARGET_ORG_ID}"
CODE="$(mgmt_curl "$TARGET_ORG_ID" POST /management/v1/users/_search -d "$(TARGET_EMAIL="$TARGET_EMAIL" python3 -c '
import json,os
print(json.dumps({
  "query":{"offset":0,"limit":20,"asc":True},
  "queries":[{"emailQuery":{"emailAddress":os.environ["TARGET_EMAIL"],"method":"TEXT_QUERY_METHOD_EQUALS"}}]
}))
')")"
[[ "$CODE" == "200" ]] || {
  echo "Search user failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
}
USER_ID="$(python3 - <<'PY'
import json
rows = json.load(open("/tmp/zitadel-body.json")).get("result") or []
print(rows[0]["id"] if rows else "")
PY
)"
[[ -n "$USER_ID" ]] || {
  echo "User not found: ${TARGET_EMAIL}" >&2
  exit 1
}
echo "USER_ID=$USER_ID"

echo "==> Load project grant"
CODE="$(mgmt_curl "$TARGET_ORG_ID" POST /management/v1/users/grants/_search -d "$(python3 -c "
import json
print(json.dumps({
  'query':{'offset':0,'limit':50,'asc':True},
  'queries':[
    {'projectIdQuery':{'projectId':'${PROJECT_ID}'}},
    {'userIdQuery':{'userId':'${USER_ID}'}},
  ],
}))
")" )"
[[ "$CODE" == "200" ]] || {
  echo "Search grants failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
}

eval "$(REMOVE_ROLE="$REMOVE_ROLE" python3 - <<'PY'
import json, os, shlex
role = os.environ["REMOVE_ROLE"]
rows = json.load(open("/tmp/zitadel-body.json")).get("result") or []
if not rows:
    print("GRANT_ID=")
    print("BEFORE=")
    print("AFTER=")
    print("CHANGED=0")
else:
    g = rows[0]
    before = list(g.get("roleKeys") or [])
    after = [k for k in before if k != role]
    print("GRANT_ID=" + shlex.quote(g.get("id") or ""))
    print("BEFORE=" + shlex.quote(" ".join(before)))
    print("AFTER=" + shlex.quote(" ".join(after)))
    print("CHANGED=" + ("1" if before != after else "0"))
PY
)"

if [[ -z "${GRANT_ID}" ]]; then
  echo "No project grant for user — nothing to remove"
  exit 0
fi

echo "BEFORE=${BEFORE}"
echo "AFTER=${AFTER}"

if [[ "${CHANGED}" != "1" ]]; then
  echo "Role ${REMOVE_ROLE} already absent — OK"
  exit 0
fi

ROLE_JSON="$(AFTER="$AFTER" python3 -c '
import json,os
keys=[k for k in os.environ.get("AFTER","").split() if k]
print(json.dumps({"roleKeys": keys}))
')"

CODE="$(mgmt_curl "$TARGET_ORG_ID" PUT "/management/v1/users/${USER_ID}/grants/${GRANT_ID}" \
  -d "${ROLE_JSON}")"
if [[ "$CODE" == "200" ]]; then
  echo "Updated grant ${GRANT_ID}: removed ${REMOVE_ROLE}"
elif grep -Eqi 'not been changed|не измен|NO_CHANGES|COMMAND-Rs8fy' /tmp/zitadel-body.json; then
  echo "Grant unchanged (already applied)"
else
  echo "Grant update failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
fi

echo "OK email=${TARGET_EMAIL} org=${TARGET_ORG_ID} removed=${REMOVE_ROLE}"
