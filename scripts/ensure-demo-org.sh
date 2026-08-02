#!/usr/bin/env bash
# Create (or reuse) a client org, grant masterdoc-toir feature keys, invite a human via email.
#
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN, ZITADEL_ORG_ID (platform/owner org)
# Optional:
#   DEMO_ORG_NAME (default "Fixaverse Demo")
#   INVITE_EMAIL (default mail@antonbutov.com)
#   INVITE_GIVEN_NAME / INVITE_FAMILY_NAME
#   INVITE_ROLE_KEYS (space-separated feature keys, default "admin")
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
PLATFORM_ORG_ID="${ZITADEL_ORG_ID:?}"
DEMO_ORG_NAME="${DEMO_ORG_NAME:-Fixaverse Demo}"
INVITE_EMAIL="${INVITE_EMAIL:-mail@antonbutov.com}"
INVITE_GIVEN_NAME="${INVITE_GIVEN_NAME:-Anton}"
INVITE_FAMILY_NAME="${INVITE_FAMILY_NAME:-Butov}"
INVITE_ROLE_KEYS="${INVITE_ROLE_KEYS:-admin}"
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
find_project_grant_id() {
  DEMO_ORG_ID="$DEMO_ORG_ID" PROJECT_ID="$PROJECT_ID" python3 - <<'PY'
import json, os
org = os.environ["DEMO_ORG_ID"]
project = os.environ["PROJECT_ID"]
body = json.load(open("/tmp/zitadel-body.json"))
rows = body.get("result") or body.get("grants") or body.get("projectGrants") or []
for g in rows:
    gid = g.get("grantId") or g.get("id") or ""
    pid = g.get("projectId") or project
    cand = [
        g.get("grantedOrgId"),
        g.get("grantedOrganizationId"),
        (g.get("grantedOrg") or {}).get("id"),
        (g.get("grantedOrganization") or {}).get("id"),
    ]
    if pid and pid != project:
        continue
    if org in {c for c in cand if c}:
        print(gid)
        raise SystemExit
matches = []
for g in rows:
    gid = g.get("grantId") or g.get("id") or ""
    pid = g.get("projectId") or ""
    if (not pid or pid == project) and gid:
        matches.append(gid)
if len(matches) == 1:
    print(matches[0])
PY
}

search_project_grants() {
  # ListAllProjectGrants — supports grantedOrgIdQuery; per-project _search does not.
  CODE="$(mgmt_curl "$PLATFORM_ORG_ID" POST /management/v1/projectgrants/_search \
    -d "$(DEMO_ORG_ID="$DEMO_ORG_ID" PROJECT_ID="$PROJECT_ID" python3 -c '
import json,os
print(json.dumps({
  "query":{"offset":0,"limit":100,"asc":True},
  "queries":[
    {"projectIdQuery":{"projectId":os.environ["PROJECT_ID"]}},
    {"grantedOrgIdQuery":{"grantedOrgId":os.environ["DEMO_ORG_ID"]}},
  ],
}))
')")"
  if [[ "$CODE" != "200" ]]; then
    echo "WARN: projectgrants/_search failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    CODE="$(mgmt_curl "$PLATFORM_ORG_ID" POST "/management/v1/projects/${PROJECT_ID}/grants/_search" \
      -d '{"query":{"offset":0,"limit":100,"asc":true}}')"
  fi
  if [[ "$CODE" != "200" ]]; then
    # Legacy misplaced grants: search under granted org header (see ZITADEL advisory 10014)
    CODE="$(mgmt_curl "$DEMO_ORG_ID" POST /management/v1/projectgrants/_search \
      -d "$(PROJECT_ID="$PROJECT_ID" python3 -c '
import json,os
print(json.dumps({
  "query":{"offset":0,"limit":100,"asc":True},
  "queries":[{"projectIdQuery":{"projectId":os.environ["PROJECT_ID"]}}],
}))
')")"
  fi
  [[ "$CODE" == "200" ]] || {
    echo "List project grants failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }
  echo "SEARCH=$(cat /tmp/zitadel-body.json)"
}

ROLE_KEYS_JSON="$(INVITE_ROLE_KEYS="$INVITE_ROLE_KEYS" python3 -c '
import json,os
keys=[k for k in os.environ["INVITE_ROLE_KEYS"].split() if k]
# grant all product feature keys so demo can assign any later
all_features=["board","charts","equipment","admin","black_box","engineer","tickets","asset_qr","ai","map","reports"]
print(json.dumps(sorted(set(all_features)|set(keys))))
')"

upsert_project_grant() {
  local gid="$1" org_header="$2"
  CODE="$(mgmt_curl "$org_header" PUT "/management/v1/projects/${PROJECT_ID}/grants/${gid}" \
    -d "{\"roleKeys\": ${ROLE_KEYS_JSON}}")"
  if [[ "$CODE" != "200" ]] && ! grep -qiE 'not been changed|не измен|не был изменён|NO_CHANGES|COMMAND-Rs8fy' /tmp/zitadel-body.json; then
    echo "Update project grant failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  fi
  echo "Project grant updated $gid (org=$org_header) -> ${ROLE_KEYS_JSON}"
}

search_project_grants
GRANT_ID="$(find_project_grant_id)"
GRANT_ORG_HEADER="$PLATFORM_ORG_ID"

if [[ -n "$GRANT_ID" ]]; then
  upsert_project_grant "$GRANT_ID" "$GRANT_ORG_HEADER"
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
    GRANT_ID="$(python3 -c 'import json; d=json.load(open("/tmp/zitadel-body.json")); print(d.get("id") or d.get("grantId") or "")')"
  elif [[ "$CODE" == "409" ]] || grep -qiE 'already exists' /tmp/zitadel-body.json; then
    echo "Project grant already exists — retry locate (incl. granted-org header)"
    echo "BODY=$(cat /tmp/zitadel-body.json)"
    search_project_grants
    GRANT_ID="$(find_project_grant_id)"
    if [[ -z "$GRANT_ID" ]]; then
      CODE="$(mgmt_curl "$DEMO_ORG_ID" POST /management/v1/projectgrants/_search \
        -d '{"query":{"offset":0,"limit":100,"asc":true}}')"
      echo "SEARCH_DEMO=$(cat /tmp/zitadel-body.json)"
      GRANT_ID="$(find_project_grant_id)"
      GRANT_ORG_HEADER="$DEMO_ORG_ID"
    fi
    [[ -n "$GRANT_ID" ]] || {
      echo "Project grant exists but id not found after re-search" >&2
      exit 1
    }
    upsert_project_grant "$GRANT_ID" "$GRANT_ORG_HEADER"
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
  if [[ "$CODE" == "409" ]] || grep -qiE 'уже существует|already exists|V3-DKcYh' /tmp/zitadel-body.json; then
    # Email is instance-unique: user may live in another org. Try instance-wide search.
    echo "WARN: create human 409 — search instance-wide for ${INVITE_EMAIL}"
    CODE="$(admin_curl POST /v2/users -d "$(INVITE_EMAIL="$INVITE_EMAIL" python3 -c '
import json,os
print(json.dumps({
  "query":{"offset":0,"limit":20,"asc":True},
  "queries":[{"emailQuery":{"emailAddress":os.environ["INVITE_EMAIL"],"method":"TEXT_QUERY_METHOD_EQUALS"}}]
}))
')")"
    if [[ "$CODE" != "200" ]]; then
      CODE="$(admin_curl POST /admin/v1/users/_search -d "$(INVITE_EMAIL="$INVITE_EMAIL" python3 -c '
import json,os
print(json.dumps({
  "query":{"offset":0,"limit":20,"asc":True},
  "queries":[{"emailQuery":{"emailAddress":os.environ["INVITE_EMAIL"],"method":"TEXT_QUERY_METHOD_EQUALS"}}]
}))
')")"
    fi
    USER_ID="$(python3 -c '
import json
d=json.load(open("/tmp/zitadel-body.json"))
rows=d.get("result") or d.get("users") or []
print(rows[0].get("userId") or rows[0].get("id") or "" if rows else "")
' 2>/dev/null || true)"
    OWNER="$(python3 -c '
import json
d=json.load(open("/tmp/zitadel-body.json"))
rows=d.get("result") or d.get("users") or []
if not rows: print(""); raise SystemExit
u=rows[0]
print(u.get("details",{}).get("resourceOwner") or u.get("resourceOwner") or u.get("orgId") or "")
' 2>/dev/null || true)"
    if [[ -n "$USER_ID" && "$OWNER" != "$DEMO_ORG_ID" ]]; then
      echo "Create human failed: ${INVITE_EMAIL} already belongs to org ${OWNER:-unknown}, not ${DEMO_ORG_ID}." >&2
      echo "Use a plus-address for this org (e.g. mail+smoke@antonbutov.com) — Zitadel emails are instance-unique." >&2
      exit 1
    fi
    [[ -n "$USER_ID" ]] || {
      echo "Create human failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
      exit 1
    }
    echo "Resolved existing USER_ID=$USER_ID in this org after 409"
  else
    [[ "$CODE" == "200" || "$CODE" == "201" ]] || {
      echo "Create human failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
      exit 1
    }
    USER_ID="$(python3 -c 'import json; d=json.load(open("/tmp/zitadel-body.json")); print(d.get("userId") or d.get("id") or "")')"
    [[ -n "$USER_ID" ]] || {
      echo "No user id: $(cat /tmp/zitadel-body.json)" >&2
      exit 1
    }
  fi
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
# Merge requested keys with any existing grant keys so we never wipe other features.
EXISTING_KEYS="$(python3 -c 'import json; r=json.load(open("/tmp/zitadel-body.json")).get("result") or []; print(" ".join((r[0].get("roleKeys") or []) if r else []))')"
USER_ROLES_JSON="$(INVITE_ROLE_KEYS="$INVITE_ROLE_KEYS" EXISTING_KEYS="$EXISTING_KEYS" python3 -c '
import json,os
keys=set(k for k in os.environ.get("EXISTING_KEYS","").split() if k)
keys.update(k for k in os.environ.get("INVITE_ROLE_KEYS","").split() if k)
print(json.dumps(sorted(keys)))
')"

if [[ -n "$UG_ID" ]]; then
  CODE="$(mgmt_curl "$DEMO_ORG_ID" PUT "/management/v1/users/${USER_ID}/grants/${UG_ID}" \
    -d "{\"roleKeys\": ${USER_ROLES_JSON}}")"
  if [[ "$CODE" != "200" ]] && ! grep -qiE 'not been changed|не измен|не был изменён|NO_CHANGES|COMMAND-Rs8fy|User grant has not been changed' /tmp/zitadel-body.json; then
    echo "Update user grant failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  fi
  echo "Updated user grant $UG_ID -> ${USER_ROLES_JSON}"
else
  CODE="$(mgmt_curl "$DEMO_ORG_ID" POST "/management/v1/users/${USER_ID}/grants" \
    -d "{\"projectId\":\"${PROJECT_ID}\",\"roleKeys\": ${USER_ROLES_JSON}}")"
  [[ "$CODE" == "200" || "$CODE" == "201" ]] || {
    echo "Create user grant failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }
  echo "Created user grant -> ${USER_ROLES_JSON}"
fi

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
elif grep -qiE 'уже инициализирован|already.*(init|active)|COMMAND-EF34g' /tmp/zitadel-body.json; then
  echo "INVITE_SENT=skipped (user already initialized)"
else
  echo "Invite send failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
fi

echo "DEMO_ORG_NAME=${DEMO_ORG_NAME}"
echo "DEMO_ORG_ID=${DEMO_ORG_ID}"
echo "INVITE_EMAIL=${INVITE_EMAIL}"
echo "OK"
