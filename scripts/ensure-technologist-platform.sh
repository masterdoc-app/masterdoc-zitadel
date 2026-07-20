#!/usr/bin/env bash
# Idempotent platform patch for technolog client:
# - project role `technologist`
# - OIDC web redirects for app.fixaverse.ru
# - user grant for GRANT_USER_EMAIL
#
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN, ZITADEL_ORG_ID
# Optional: GRANT_USER_EMAIL (default: mail@antonbutov.com)
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
ORG_ID="${ZITADEL_ORG_ID:?}"
GRANT_USER_EMAIL="${GRANT_USER_EMAIL:-mail@antonbutov.com}"
API="https://${DOMAIN}"

curl_api() {
  local method="$1" path="$2"
  shift 2
  curl -sS -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -X "$method" "${API}${path}" "$@"
}

echo "==> Search project masterdoc-toir"
PROJECTS="$(curl_api POST /management/v1/projects/_search \
  -d '{"query":{"offset":0,"limit":100,"asc":true},"queries":[{"nameQuery":{"name":"masterdoc-toir","method":"TEXT_QUERY_METHOD_EQUALS"}}]}')"
PROJECT_ID="$(printf '%s' "$PROJECTS" | python3 -c 'import json,sys; r=(json.load(sys.stdin).get("result") or []); print(r[0]["id"] if r else "")')"
[[ -n "$PROJECT_ID" ]] || { echo "Project masterdoc-toir not found" >&2; exit 1; }
echo "PROJECT_ID=$PROJECT_ID"

echo "==> Ensure role technologist"
ROLE_CODE="$(curl -sS -o /tmp/zitadel-role.json -w '%{http_code}' \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "x-zitadel-orgid: ${ORG_ID}" \
  -X POST "${API}/management/v1/projects/${PROJECT_ID}/roles" \
  -d '{"roleKey":"technologist","displayName":"Technologist"}')"
ROLE_BODY="$(cat /tmp/zitadel-role.json)"
if [[ "$ROLE_CODE" == "200" || "$ROLE_CODE" == "201" ]]; then
  echo "Role technologist created"
elif echo "$ROLE_BODY" | grep -qiE 'already|exist|duplicate'; then
  echo "Role technologist already present ($ROLE_CODE)"
else
  EXISTING="$(curl_api POST "/management/v1/projects/${PROJECT_ID}/roles/_search" \
    -d '{"query":{"offset":0,"limit":100,"asc":true}}' || true)"
  if echo "$EXISTING" | grep -q 'technologist'; then
    echo "Role technologist already listed"
  else
    echo "Failed to add role ($ROLE_CODE): $ROLE_BODY" >&2
    exit 1
  fi
fi

echo "==> Find OIDC app masterdoc-kmp-web"
APPS="$(curl_api POST "/management/v1/projects/${PROJECT_ID}/apps/_search" \
  -d '{"query":{"offset":0,"limit":100,"asc":true}}')"
eval "$(printf '%s' "$APPS" | python3 -c '
import json, sys
apps = json.load(sys.stdin)
web = next((a for a in (apps.get("result") or []) if a.get("name") == "masterdoc-kmp-web"), None)
if not web:
    raise SystemExit("masterdoc-kmp-web not found")
oidc = web.get("oidcConfig") or {}
print("APP_ID=" + web["id"])
print("CLIENT_ID=" + (oidc.get("clientId") or ""))
print("REDIRECTS_JSON=" + json.dumps(oidc.get("redirectUris") or []))
print("POST_LOGOUT_JSON=" + json.dumps(oidc.get("postLogoutRedirectUris") or []))
')"
echo "APP_ID=$APP_ID CLIENT_ID=$CLIENT_ID"

echo "==> Merge OIDC redirect URIs"
UPDATE_BODY="$(REDIRECTS_JSON="$REDIRECTS_JSON" POST_LOGOUT_JSON="$POST_LOGOUT_JSON" python3 -c '
import json, os, sys
needed_r = [
    "https://copilot.fixaverse.ru/auth/callback",
    "https://app.fixaverse.ru/auth/callback",
    "http://localhost:8080/auth/callback",
]
needed_p = [
    "https://copilot.fixaverse.ru/",
    "https://app.fixaverse.ru/",
    "http://localhost:8080/",
]
merged_r = list(dict.fromkeys(json.loads(os.environ["REDIRECTS_JSON"]) + needed_r))
merged_p = list(dict.fromkeys(json.loads(os.environ["POST_LOGOUT_JSON"]) + needed_p))
print(json.dumps({
    "redirectUris": merged_r,
    "postLogoutRedirectUris": merged_p,
    "responseTypes": ["OIDC_RESPONSE_TYPE_CODE"],
    "grantTypes": ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"],
    "appType": "OIDC_APP_TYPE_USER_AGENT",
    "authMethodType": "OIDC_AUTH_METHOD_TYPE_NONE",
    "version": "OIDC_VERSION_1_0",
    "accessTokenType": "OIDC_TOKEN_TYPE_BEARER",
    "idTokenRoleAssertion": True,
    "accessTokenRoleAssertion": True,
    "idTokenUserinfoAssertion": True,
    "clockSkew": "0s",
    "devMode": True,
}))
print("redirects ->", merged_r, file=sys.stderr)
')"

UPD_CODE="$(curl -sS -o /tmp/zitadel-oidc.json -w '%{http_code}' \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "x-zitadel-orgid: ${ORG_ID}" \
  -X PUT "${API}/management/v1/projects/${PROJECT_ID}/apps/${APP_ID}/oidc_config" \
  -d "$UPDATE_BODY")"
if [[ "$UPD_CODE" != "200" ]]; then
  UPD_CODE="$(curl -sS -o /tmp/zitadel-oidc.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -X PUT "${API}/management/v1/projects/${PROJECT_ID}/apps/${APP_ID}/oidc" \
    -d "$UPDATE_BODY")"
fi
[[ "$UPD_CODE" == "200" ]] || { echo "OIDC update failed ($UPD_CODE): $(cat /tmp/zitadel-oidc.json)" >&2; exit 1; }
echo "OIDC redirects updated"

echo "==> Find user ${GRANT_USER_EMAIL}"
USERS="$(curl_api POST /v2/users \
  -d "$(GRANT_USER_EMAIL="$GRANT_USER_EMAIL" python3 -c '
import json, os
print(json.dumps({
  "query": {"offset": 0, "limit": 20, "asc": True},
  "queries": [{
    "emailQuery": {
      "emailAddress": os.environ["GRANT_USER_EMAIL"],
      "method": "TEXT_QUERY_METHOD_EQUALS",
    }
  }],
}))
')")"
USER_ID="$(printf '%s' "$USERS" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for u in (d.get("result") or []):
    uid = u.get("userId") or (u.get("user") or {}).get("userId") or u.get("id")
    if uid:
        print(uid); break
')"

if [[ -z "$USER_ID" ]]; then
  USERS="$(curl_api POST /management/v1/users/_search \
    -d "$(GRANT_USER_EMAIL="$GRANT_USER_EMAIL" python3 -c '
import json, os
print(json.dumps({
  "query": {"offset": 0, "limit": 20, "asc": True},
  "queries": [{"emailQuery": {"email": os.environ["GRANT_USER_EMAIL"], "method": "TEXT_QUERY_METHOD_EQUALS"}}],
}))
')")"
  USER_ID="$(printf '%s' "$USERS" | python3 -c 'import json,sys; r=(json.load(sys.stdin).get("result") or []); print(r[0].get("id","") if r else "")')"
fi

if [[ -z "$USER_ID" ]]; then
  echo "User ${GRANT_USER_EMAIL} not found — role/OIDC done, grant skipped" >&2
  echo "WEB_CLIENT_ID=${CLIENT_ID}"
  exit 0
fi
echo "USER_ID=$USER_ID"

echo "==> Ensure user grant includes technologist"
GRANTS="$(curl_api POST /management/v1/users/grants/_search \
  -d "$(python3 -c "
import json
print(json.dumps({
  'query': {'offset': 0, 'limit': 100, 'asc': True},
  'queries': [
    {'projectIdQuery': {'projectId': '${PROJECT_ID}'}},
    {'userIdQuery': {'userId': '${USER_ID}'}},
  ],
}))
")" || echo '{"result":[]}')"

eval "$(printf '%s' "$GRANTS" | python3 -c '
import json, sys
r = (json.load(sys.stdin).get("result") or [])
if not r:
    print("GRANT_ID=")
    print("EXISTING_ROLES=")
else:
    print("GRANT_ID=" + (r[0].get("id") or ""))
    print("EXISTING_ROLES=" + " ".join(r[0].get("roleKeys") or []))
')"

if [[ -n "$GRANT_ID" ]]; then
  ROLE_JSON="$(EXISTING_ROLES="$EXISTING_ROLES" python3 -c '
import json, os
roles = set(os.environ.get("EXISTING_ROLES", "").split())
roles.discard("")
roles.add("technologist")
print(json.dumps({"roleKeys": sorted(roles)}))
')"
  GCODE="$(curl -sS -o /tmp/zitadel-grant.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -X PUT "${API}/management/v1/users/${USER_ID}/grants/${GRANT_ID}" \
    -d "$ROLE_JSON")"
  [[ "$GCODE" == "200" ]] || { echo "Grant update failed ($GCODE): $(cat /tmp/zitadel-grant.json)" >&2; exit 1; }
  echo "Updated grant $GRANT_ID -> $ROLE_JSON"
else
  GCODE="$(curl -sS -o /tmp/zitadel-grant.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -X POST "${API}/management/v1/users/${USER_ID}/grants" \
    -d "{\"projectId\":\"${PROJECT_ID}\",\"roleKeys\":[\"technologist\"]}")"
  [[ "$GCODE" == "200" || "$GCODE" == "201" ]] || { echo "Grant create failed ($GCODE): $(cat /tmp/zitadel-grant.json)" >&2; exit 1; }
  echo "Created grant with technologist"
fi

echo "WEB_CLIENT_ID=${CLIENT_ID}"
echo "OK"
