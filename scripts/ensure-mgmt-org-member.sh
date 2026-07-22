#!/usr/bin/env bash
# Grant the machine-user PAT ORG_USER_MANAGER on client orgs so gateway can
# revoke invites (user.delete). Idempotent: add or update member roles.
#
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN
# Optional:
#   EXTRA_ORG_IDS — space-separated client org ids (required for any grant)
#   MGMT_ORG_ROLES — default "ORG_USER_MANAGER" (space-separated)
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
EXTRA_ORG_IDS="${EXTRA_ORG_IDS:-}"
MGMT_ORG_ROLES="${MGMT_ORG_ROLES:-ORG_USER_MANAGER}"
API="https://${DOMAIN}"

if [[ -z "${EXTRA_ORG_IDS// }" ]]; then
  echo "EXTRA_ORG_IDS is empty — nothing to grant" >&2
  exit 1
fi

mgmt_curl() {
  local org_id="$1" method="$2" path="$3"
  shift 3
  curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${org_id}" \
    -X "$method" "${API}${path}" "$@"
}

auth_curl() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -X "$method" "${API}${path}" "$@"
}

echo "==> Resolve PAT user id (auth/v1/users/me)"
CODE="$(auth_curl GET /auth/v1/users/me)"
[[ "$CODE" == "200" ]] || {
  echo "GetMyUser failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
}
USER_ID="$(python3 - <<'PY'
import json
u = json.load(open("/tmp/zitadel-body.json")).get("user") or {}
print(u.get("id") or "")
PY
)"
USER_NAME="$(python3 - <<'PY'
import json
u = json.load(open("/tmp/zitadel-body.json")).get("user") or {}
print(u.get("userName") or u.get("preferredLoginName") or "")
PY
)"
[[ -n "$USER_ID" ]] || {
  echo "No user id in GetMyUser: $(cat /tmp/zitadel-body.json)" >&2
  exit 1
}
echo "USER_ID=$USER_ID USER_NAME=$USER_NAME"

ROLES_JSON="$(MGMT_ORG_ROLES="$MGMT_ORG_ROLES" python3 -c '
import json, os
print(json.dumps(os.environ["MGMT_ORG_ROLES"].split()))
')"

ensure_org() {
  local org_id="$1"
  echo "==> Org member org=$org_id roles=$MGMT_ORG_ROLES user=$USER_ID"

  CODE="$(mgmt_curl "$org_id" POST /management/v1/orgs/me/members/_search -d "$(USER_ID="$USER_ID" python3 -c '
import json, os
print(json.dumps({
  "query": {"offset": 0, "limit": 100, "asc": True},
  "queries": [{"userIdQuery": {"userId": os.environ["USER_ID"]}}],
}))
')")"
  [[ "$CODE" == "200" ]] || {
    echo "ListOrgMembers failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }

  EXISTS="$(USER_ID="$USER_ID" python3 - <<'PY'
import json, os
uid = os.environ["USER_ID"]
for m in json.load(open("/tmp/zitadel-body.json")).get("result") or []:
    if m.get("userId") == uid:
        print("yes"); break
else:
    print("no")
PY
)"

  BODY="$(USER_ID="$USER_ID" ROLES_JSON="$ROLES_JSON" python3 -c '
import json, os
print(json.dumps({
  "userId": os.environ["USER_ID"],
  "roles": json.loads(os.environ["ROLES_JSON"]),
}))
')"

  if [[ "$EXISTS" == "yes" ]]; then
    CODE="$(mgmt_curl "$org_id" PUT "/management/v1/orgs/me/members/${USER_ID}" -d "$BODY")"
    if [[ "$CODE" == "200" ]]; then
      echo "OK org=$org_id (updated)"
      return 0
    fi
    echo "UpdateOrgMember failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  fi

  CODE="$(mgmt_curl "$org_id" POST /management/v1/orgs/me/members -d "$BODY")"
  if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
    echo "OK org=$org_id (added)"
    return 0
  fi
  # Already exists race / conflict → try update
  if [[ "$CODE" == "409" || "$CODE" == "400" ]]; then
    CODE="$(mgmt_curl "$org_id" PUT "/management/v1/orgs/me/members/${USER_ID}" -d "$BODY")"
    if [[ "$CODE" == "200" ]]; then
      echo "OK org=$org_id (updated after conflict)"
      return 0
    fi
  fi
  echo "AddOrgMember failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
}

for oid in $EXTRA_ORG_IDS; do
  ensure_org "$oid"
done

echo "Done."
