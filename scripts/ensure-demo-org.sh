#!/usr/bin/env bash
# Create (or reuse) a client org, grant masterdoc-toir feature keys, invite a human via email.
#
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN, ZITADEL_ORG_ID (platform/owner org)
# Optional:
#   DEMO_ORG_NAME (default "Fixaverse Demo")
#   INVITE_EMAIL (default mail@antonbutov.com)
#   INVITE_GIVEN_NAME / INVITE_FAMILY_NAME
#   INVITE_ROLE_KEYS (space-separated feature keys, default "user_invite")
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
PLATFORM_ORG_ID="${ZITADEL_ORG_ID:?}"
DEMO_ORG_NAME="${DEMO_ORG_NAME:-Fixaverse Demo}"
INVITE_EMAIL="${INVITE_EMAIL:-mail@antonbutov.com}"
INVITE_GIVEN_NAME="${INVITE_GIVEN_NAME:-Anton}"
INVITE_FAMILY_NAME="${INVITE_FAMILY_NAME:-Butov}"
INVITE_ROLE_KEYS="${INVITE_ROLE_KEYS:-user_invite}"
INVITE_APP_NAME="${INVITE_APP_NAME:-Fixaverse}"
INVITE_LANG="${INVITE_LANG:-ru}"
PROJECT_NAME="masterdoc-toir"
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

admin_curl() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -X "$method" "${API}${path}" "$@"
}

echo "==> Find project ${PROJECT_NAME} in platform org"
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
        print(p["id"]); break
PY
)"
[[ -n "$PROJECT_ID" ]] || {
  echo "Project ${PROJECT_NAME} not found in platform org ${PLATFORM_ORG_ID}" >&2
  exit 1
}
echo "PROJECT_ID=$PROJECT_ID"

echo "==> Find or create org '${DEMO_ORG_NAME}'"
CODE="$(admin_curl POST /admin/v1/orgs/_search -d "$(DEMO_ORG_NAME="$DEMO_ORG_NAME" python3 -c '
import json,os
print(json.dumps({
  "query":{"offset":0,"limit":20,"asc":True},
  "queries":[{"nameQuery":{"name":os.environ["DEMO_ORG_NAME"],"method":"TEXT_QUERY_METHOD_EQUALS"}}]
}))
')")"
[[ "$CODE" == "200" ]] || {
  echo "ListOrgs failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
}
DEMO_ORG_ID="$(DEMO_ORG_NAME="$DEMO_ORG_NAME" python3 - <<'PY'
import json, os
name = os.environ["DEMO_ORG_NAME"]
for o in json.load(open("/tmp/zitadel-body.json")).get("result") or []:
    if o.get("name") == name:
        print(o.get("id") or ""); break
PY
)"

if [[ -z "$DEMO_ORG_ID" ]]; then
  echo "Creating organization via v2"
  CODE="$(admin_curl POST /v2/organizations -d "$(DEMO_ORG_NAME="$DEMO_ORG_NAME" python3 -c '
import json,os
print(json.dumps({"name": os.environ["DEMO_ORG_NAME"]}))
')")"
  [[ "$CODE" == "200" || "$CODE" == "201" ]] || {
    echo "AddOrganization failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }
  DEMO_ORG_ID="$(python3 -c 'import json; d=json.load(open("/tmp/zitadel-body.json")); print(d.get("organizationId") or d.get("id") or "")')"
  [[ -n "$DEMO_ORG_ID" ]] || {
    echo "No org id in create response: $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }
fi
echo "DEMO_ORG_ID=$DEMO_ORG_ID"

echo "==> Ensure project grant to demo org"
CODE="$(mgmt_curl "$PLATFORM_ORG_ID" POST "/management/v1/projects/${PROJECT_ID}/grants/_search" \
  -d '{"query":{"offset":0,"limit":100,"asc":true}}')"
[[ "$CODE" == "200" ]] || {
  echo "List project grants failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
}
GRANT_ID="$(DEMO_ORG_ID="$DEMO_ORG_ID" python3 - <<'PY'
import json, os
org = os.environ["DEMO_ORG_ID"]
for g in json.load(open("/tmp/zitadel-body.json")).get("result") or []:
    if g.get("grantedOrgId") == org:
        print(g.get("id") or ""); break
PY
)"

ROLE_KEYS_JSON="$(INVITE_ROLE_KEYS="$INVITE_ROLE_KEYS" python3 -c '
import json,os
keys=[k for k in os.environ["INVITE_ROLE_KEYS"].split() if k]
# grant all product feature keys so demo can assign any later
all_features=["board","charts","copilot","equipment","user_invite"]
print(json.dumps(sorted(set(all_features)|set(keys))))
')"

if [[ -n "$GRANT_ID" ]]; then
  CODE="$(mgmt_curl "$PLATFORM_ORG_ID" PUT "/management/v1/projects/${PROJECT_ID}/grants/${GRANT_ID}" \
    -d "{\"roleKeys\": ${ROLE_KEYS_JSON}}")"
  if [[ "$CODE" != "200" ]] && ! grep -qiE 'not been changed|не измен|не был изменён|NO_CHANGES|COMMAND-Rs8fy' /tmp/zitadel-body.json; then
    echo "Update project grant failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  fi
  echo "Project grant updated $GRANT_ID"
else
  CODE="$(mgmt_curl "$PLATFORM_ORG_ID" POST "/management/v1/projects/${PROJECT_ID}/grants" \
    -d "$(DEMO_ORG_ID="$DEMO_ORG_ID" ROLE_KEYS_JSON="$ROLE_KEYS_JSON" python3 -c '
import json,os
print(json.dumps({
  "grantedOrgId": os.environ["DEMO_ORG_ID"],
  "roleKeys": json.loads(os.environ["ROLE_KEYS_JSON"]),
}))
')")"
  if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
    echo "Project grant created"
  elif [[ "$CODE" == "409" ]] || grep -qiE 'already exists' /tmp/zitadel-body.json; then
    echo "Project grant already exists (race/search miss) — OK"
  else
    echo "Add project grant failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  fi
fi

echo "==> Find or invite ${INVITE_EMAIL} in demo org"
CODE="$(mgmt_curl "$DEMO_ORG_ID" POST /management/v1/users/_search -d "$(INVITE_EMAIL="$INVITE_EMAIL" python3 -c '
import json,os
print(json.dumps({
  "query":{"offset":0,"limit":20,"asc":True},
  "queries":[{"emailQuery":{"emailAddress":os.environ["INVITE_EMAIL"],"method":"TEXT_QUERY_METHOD_EQUALS"}}]
}))
')")"
[[ "$CODE" == "200" ]] || {
  echo "Search users failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
}
USER_ID="$(python3 -c 'import json; r=json.load(open("/tmp/zitadel-body.json")).get("result") or []; print(r[0].get("id","") if r else "")')"

if [[ -z "$USER_ID" ]]; then
  echo "Creating human (ru) then invite with applicationName=${INVITE_APP_NAME}"
  CODE="$(mgmt_curl "$DEMO_ORG_ID" POST /v2/users/human -d "$(
    INVITE_EMAIL="$INVITE_EMAIL" INVITE_GIVEN_NAME="$INVITE_GIVEN_NAME" \
    INVITE_FAMILY_NAME="$INVITE_FAMILY_NAME" INVITE_LANG="$INVITE_LANG" python3 -c '
import json,os
print(json.dumps({
  "profile": {
    "givenName": os.environ["INVITE_GIVEN_NAME"],
    "familyName": os.environ["INVITE_FAMILY_NAME"],
    "preferredLanguage": os.environ["INVITE_LANG"],
  },
  "email": {
    "email": os.environ["INVITE_EMAIL"],
    "isVerified": False,
  },
}))
')")"
  [[ "$CODE" == "200" || "$CODE" == "201" ]] || {
    echo "Create human failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }
  USER_ID="$(python3 -c 'import json; d=json.load(open("/tmp/zitadel-body.json")); print(d.get("userId") or d.get("id") or "")')"
  [[ -n "$USER_ID" ]] || {
    echo "No user id: $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }
else
  echo "User exists USER_ID=$USER_ID — set preferredLanguage=${INVITE_LANG} (v1 profile)"
  CODE="$(mgmt_curl "$DEMO_ORG_ID" PUT "/management/v1/users/${USER_ID}/profile" -d "$(
    INVITE_GIVEN_NAME="$INVITE_GIVEN_NAME" INVITE_FAMILY_NAME="$INVITE_FAMILY_NAME" INVITE_LANG="$INVITE_LANG" python3 -c '
import json,os
gn=os.environ["INVITE_GIVEN_NAME"]
fn=os.environ["INVITE_FAMILY_NAME"]
print(json.dumps({
  "firstName": gn,
  "lastName": fn,
  "displayName": f"{gn} {fn}",
  "preferredLanguage": os.environ["INVITE_LANG"],
}))
')")"
  if [[ "$CODE" != "200" ]]; then
    if ! grep -qiE 'not been changed|не измен|NO_CHANGES' /tmp/zitadel-body.json; then
      echo "WARN: update profile language failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    fi
  fi
fi
echo "USER_ID=$USER_ID"

echo "==> Send invite code (applicationName=${INVITE_APP_NAME})"
CODE="$(mgmt_curl "$DEMO_ORG_ID" POST "/v2/users/${USER_ID}/invite_code" -d "$(
  INVITE_APP_NAME="$INVITE_APP_NAME" python3 -c '
import json,os
print(json.dumps({
  "sendCode": {
    "applicationName": os.environ["INVITE_APP_NAME"],
  },
}))
')")"
if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
  echo "INVITE_SENT=yes"
else
  echo "Invite send failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
fi

echo "==> Ensure user project grant (${INVITE_ROLE_KEYS})"
CODE="$(mgmt_curl "$DEMO_ORG_ID" POST /management/v1/users/grants/_search -d "$(python3 -c "
import json
print(json.dumps({
  'query':{'offset':0,'limit':50,'asc':True},
  'queries':[
    {'projectIdQuery':{'projectId':'${PROJECT_ID}'}},
    {'userIdQuery':{'userId':'${USER_ID}'}},
  ],
}))
")" )"
UG_ID="$(python3 -c 'import json; r=json.load(open("/tmp/zitadel-body.json")).get("result") or []; print(r[0].get("id","") if r else "")')"
USER_ROLES_JSON="$(INVITE_ROLE_KEYS="$INVITE_ROLE_KEYS" python3 -c 'import json,os; print(json.dumps([k for k in os.environ["INVITE_ROLE_KEYS"].split() if k]))')"

if [[ -n "$UG_ID" ]]; then
  CODE="$(mgmt_curl "$DEMO_ORG_ID" PUT "/management/v1/users/${USER_ID}/grants/${UG_ID}" \
    -d "{\"roleKeys\": ${USER_ROLES_JSON}}")"
  if [[ "$CODE" != "200" ]] && ! grep -qiE 'not been changed|не измен|не был изменён|NO_CHANGES|COMMAND-Rs8fy|User grant has not been changed' /tmp/zitadel-body.json; then
    echo "Update user grant failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  fi
else
  CODE="$(mgmt_curl "$DEMO_ORG_ID" POST "/management/v1/users/${USER_ID}/grants" \
    -d "{\"projectId\":\"${PROJECT_ID}\",\"roleKeys\": ${USER_ROLES_JSON}}")"
  [[ "$CODE" == "200" || "$CODE" == "201" ]] || {
    echo "Create user grant failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }
fi

echo "DEMO_ORG_NAME=${DEMO_ORG_NAME}"
echo "DEMO_ORG_ID=${DEMO_ORG_ID}"
echo "INVITE_EMAIL=${INVITE_EMAIL}"
echo "OK"
