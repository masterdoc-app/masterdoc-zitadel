#!/usr/bin/env bash
# Idempotent IdP bootstrap/patch for technolog web client (REST Management API).
# Creates project/roles/OIDC app if missing; always merges app.fixaverse.ru redirects
# and grants technologist to GRANT_USER_EMAIL.
#
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN, ZITADEL_ORG_ID
# Optional: GRANT_USER_EMAIL (default: mail@antonbutov.com)
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
ORG_ID="${ZITADEL_ORG_ID:?}"
GRANT_USER_EMAIL="${GRANT_USER_EMAIL:-mail@antonbutov.com}"
API="https://${DOMAIN}"
PROJECT_NAME="masterdoc-toir"
WEB_APP_NAME="masterdoc-kmp-web"
NATIVE_APP_NAME="masterdoc-kmp-native"

curl_json() {
  local method="$1" path="$2"
  shift 2
  curl -sS -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -X "$method" "${API}${path}" "$@"
}

http_code_body() {
  # usage: http_code_body METHOD PATH [curl -d ...]
  # sets BODY_FILE response; echoes http code
  local method="$1" path="$2"
  shift 2
  curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -X "$method" "${API}${path}" "$@"
}

echo "==> List projects"
export PROJECT_NAME
PROJECTS="$(curl_json POST /management/v1/projects/_search \
  -d '{"query":{"offset":0,"limit":100,"asc":true}}')"
PROJECT_ID="$(printf '%s' "$PROJECTS" | PROJECT_NAME="$PROJECT_NAME" python3 -c '
import json,sys,os
name=os.environ["PROJECT_NAME"]
r=json.load(sys.stdin).get("result") or []
for p in r:
    if p.get("name")==name:
        print(p["id"]); break
')"

if [[ -z "$PROJECT_ID" ]]; then
  echo "==> Create project ${PROJECT_NAME}"
  CODE="$(http_code_body POST /management/v1/projects -d '{
    "name":"masterdoc-toir",
    "projectRoleAssertion":true,
    "projectRoleCheck":true,
    "hasProjectCheck":true
  }')"
  [[ "$CODE" == "200" || "$CODE" == "201" ]] || {
    echo "Create project failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }
  PROJECT_ID="$(python3 -c 'import json; print(json.load(open("/tmp/zitadel-body.json")).get("id",""))')"
  [[ -n "$PROJECT_ID" ]] || { echo "No project id in create response" >&2; exit 1; }
fi
echo "PROJECT_ID=$PROJECT_ID"

ensure_role() {
  local key="$1" display="$2"
  CODE="$(http_code_body POST "/management/v1/projects/${PROJECT_ID}/roles" \
    -d "{\"roleKey\":\"${key}\",\"displayName\":\"${display}\"}")"
  if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
    echo "Role ${key} created"
  elif grep -qiE 'already|exist|duplicate' /tmp/zitadel-body.json; then
    echo "Role ${key} exists"
  else
    # confirm via search
    ROLES="$(curl_json POST "/management/v1/projects/${PROJECT_ID}/roles/_search" \
      -d '{"query":{"offset":0,"limit":100,"asc":true}}' || true)"
    if echo "$ROLES" | grep -q "\"${key}\""; then
      echo "Role ${key} already listed"
    else
      echo "Role ${key} failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
      exit 1
    fi
  fi
}

echo "==> Ensure roles"
ensure_role admin Administrator
ensure_role dispatcher Dispatcher
ensure_role engineer Engineer
ensure_role requester Requester
ensure_role reporter Reporter
ensure_role technologist Technologist

echo "==> Find/create OIDC apps"
APPS="$(curl_json POST "/management/v1/projects/${PROJECT_ID}/apps/_search" \
  -d '{"query":{"offset":0,"limit":100,"asc":true}}')"

WEB_APP_ID="$(printf '%s' "$APPS" | python3 -c '
import json,sys
name="masterdoc-kmp-web"
for a in (json.load(sys.stdin).get("result") or []):
    if a.get("name")==name:
        print(a["id"]); break
')"
CLIENT_ID=""

OIDC_WEB_CREATE='{
  "name": "masterdoc-kmp-web",
  "redirectUris": [
    "https://copilot.fixaverse.ru/auth/callback",
    "https://app.fixaverse.ru/auth/callback",
    "http://localhost:8080/auth/callback"
  ],
  "postLogoutRedirectUris": [
    "https://copilot.fixaverse.ru/",
    "https://app.fixaverse.ru/",
    "http://localhost:8080/"
  ],
  "responseTypes": ["OIDC_RESPONSE_TYPE_CODE"],
  "grantTypes": ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"],
  "appType": "OIDC_APP_TYPE_USER_AGENT",
  "authMethodType": "OIDC_AUTH_METHOD_TYPE_NONE",
  "version": "OIDC_VERSION_1_0",
  "accessTokenType": "OIDC_TOKEN_TYPE_BEARER",
  "idTokenRoleAssertion": true,
  "accessTokenRoleAssertion": true,
  "idTokenUserinfoAssertion": true,
  "clockSkew": "0s",
  "devMode": true
}'

if [[ -z "$WEB_APP_ID" ]]; then
  echo "==> Create web OIDC app"
  CODE="$(http_code_body POST "/management/v1/projects/${PROJECT_ID}/apps/oidc" -d "$OIDC_WEB_CREATE")"
  [[ "$CODE" == "200" || "$CODE" == "201" ]] || {
    echo "Create web app failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }
  eval "$(python3 -c '
import json
d=json.load(open("/tmp/zitadel-body.json"))
print("WEB_APP_ID=" + (d.get("appId") or d.get("id") or ""))
cfg=d.get("clientId") or (d.get("oidcConfig") or {}).get("clientId") or ""
print("CLIENT_ID=" + cfg)
')"
else
  echo "WEB_APP_ID=$WEB_APP_ID"
  CLIENT_ID="$(printf '%s' "$APPS" | python3 -c '
import json,sys
for a in (json.load(sys.stdin).get("result") or []):
    if a.get("name")=="masterdoc-kmp-web":
        print((a.get("oidcConfig") or {}).get("clientId") or ""); break
')"
  echo "==> Update web OIDC redirects"
  CODE="$(http_code_body PUT "/management/v1/projects/${PROJECT_ID}/apps/${WEB_APP_ID}/oidc_config" -d "$OIDC_WEB_CREATE")"
  if [[ "$CODE" != "200" ]]; then
    CODE="$(http_code_body PUT "/management/v1/projects/${PROJECT_ID}/apps/${WEB_APP_ID}/oidc" -d "$OIDC_WEB_CREATE")"
  fi
  if [[ "$CODE" != "200" ]]; then
    echo "Update web OIDC skipped/failed ($CODE): $(cat /tmp/zitadel-body.json) — keeping existing app config"
  else
    echo "OIDC redirects updated"
  fi
fi
echo "CLIENT_ID=$CLIENT_ID"

NATIVE_APP_ID="$(printf '%s' "$APPS" | python3 -c '
import json,sys
for a in (json.load(sys.stdin).get("result") or []):
    if a.get("name")=="masterdoc-kmp-native":
        print(a["id"]); break
' || true)"
if [[ -z "${NATIVE_APP_ID:-}" ]]; then
  echo "==> Create native OIDC app"
  CODE="$(http_code_body POST "/management/v1/projects/${PROJECT_ID}/apps/oidc" -d '{
    "name": "masterdoc-kmp-native",
    "redirectUris": ["masterdoc://auth/callback", "http://127.0.0.1:8081/callback"],
    "postLogoutRedirectUris": ["masterdoc://auth/callback", "http://127.0.0.1:8081/callback"],
    "responseTypes": ["OIDC_RESPONSE_TYPE_CODE"],
    "grantTypes": ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"],
    "appType": "OIDC_APP_TYPE_NATIVE",
    "authMethodType": "OIDC_AUTH_METHOD_TYPE_NONE",
    "version": "OIDC_VERSION_1_0",
    "accessTokenType": "OIDC_TOKEN_TYPE_BEARER",
    "idTokenRoleAssertion": true,
    "accessTokenRoleAssertion": true,
    "idTokenUserinfoAssertion": true,
    "clockSkew": "0s",
    "devMode": true,
    "skipNativeAppSuccessPage": true
  }')"
  if [[ "$CODE" != "200" && "$CODE" != "201" ]]; then
    echo "Create native app warning ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  else
    echo "Native app created"
  fi
fi

echo "==> Find user ${GRANT_USER_EMAIL}"
USERS="$(curl_json POST /v2/users -d "$(GRANT_USER_EMAIL="$GRANT_USER_EMAIL" python3 -c '
import json,os
print(json.dumps({
  "query":{"offset":0,"limit":20,"asc":True},
  "queries":[{"emailQuery":{"emailAddress":os.environ["GRANT_USER_EMAIL"],"method":"TEXT_QUERY_METHOD_EQUALS"}}]
}))
')")"
USER_ID="$(printf '%s' "$USERS" | python3 -c '
import json,sys
for u in (json.load(sys.stdin).get("result") or []):
    uid=u.get("userId") or (u.get("user") or {}).get("userId") or u.get("id")
    if uid: print(uid); break
')"
if [[ -z "$USER_ID" ]]; then
  USERS="$(curl_json POST /management/v1/users/_search -d "$(GRANT_USER_EMAIL="$GRANT_USER_EMAIL" python3 -c '
import json,os
email=os.environ["GRANT_USER_EMAIL"]
print(json.dumps({
  "query":{"offset":0,"limit":20,"asc":True},
  "queries":[{"emailQuery":{"email":email,"method":"TEXT_QUERY_METHOD_EQUALS"}}]
}))
')")"
  USER_ID="$(printf '%s' "$USERS" | python3 -c 'import json,sys; r=json.load(sys.stdin).get("result") or []; print(r[0].get("id","") if r else "")')"
fi
if [[ -z "$USER_ID" ]]; then
  USERS="$(curl_json POST /management/v1/users/_search -d "$(GRANT_USER_EMAIL="$GRANT_USER_EMAIL" python3 -c '
import json,os
print(json.dumps({
  "query":{"offset":0,"limit":20,"asc":True},
  "queries":[{"loginNameQuery":{"loginName":os.environ["GRANT_USER_EMAIL"],"method":"TEXT_QUERY_METHOD_EQUALS"}}]
}))
')")"
  USER_ID="$(printf '%s' "$USERS" | python3 -c 'import json,sys; r=json.load(sys.stdin).get("result") or []; print(r[0].get("id","") if r else "")')"
fi
if [[ -z "$USER_ID" ]]; then
  echo "==> Listing org users (email/login) to pick grant target"
  ALL="$(curl_json POST /management/v1/users/_search -d '{"query":{"offset":0,"limit":50,"asc":true}}')"
  printf '%s' "$ALL" | python3 -c '
import json,sys
for u in (json.load(sys.stdin).get("result") or []):
    human=u.get("human") or {}
    email=(human.get("email") or {}).get("email") or ""
    preferred=u.get("preferredLoginName") or ""
    print("id=%s login=%s email=%s" % (u.get("id"), preferred, email))
'
  echo "User ${GRANT_USER_EMAIL} not found — platform ready, grant skipped" >&2
  echo "WEB_CLIENT_ID=${CLIENT_ID}"
  exit 0
fi
echo "USER_ID=$USER_ID"

echo "==> Ensure user grant includes technologist"
GRANTS="$(curl_json POST /management/v1/users/grants/_search -d "$(python3 -c "
import json
print(json.dumps({
  'query':{'offset':0,'limit':100,'asc':True},
  'queries':[
    {'projectIdQuery':{'projectId':'${PROJECT_ID}'}},
    {'userIdQuery':{'userId':'${USER_ID}'}},
  ],
}))
")" || echo '{"result":[]}')"

eval "$(printf '%s' "$GRANTS" | python3 -c '
import json,sys
r=json.load(sys.stdin).get("result") or []
if not r:
    print("GRANT_ID="); print("EXISTING_ROLES=")
else:
    print("GRANT_ID="+(r[0].get("id") or ""))
    print("EXISTING_ROLES="+" ".join(r[0].get("roleKeys") or []))
')"

if [[ -n "$GRANT_ID" ]]; then
  ROLE_JSON="$(EXISTING_ROLES="$EXISTING_ROLES" python3 -c '
import json,os
roles=set(os.environ.get("EXISTING_ROLES","").split()); roles.discard(""); roles.add("technologist")
print(json.dumps({"roleKeys":sorted(roles)}))
')"
  CODE="$(http_code_body PUT "/management/v1/users/${USER_ID}/grants/${GRANT_ID}" -d "$ROLE_JSON")"
  [[ "$CODE" == "200" ]] || { echo "Grant update failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2; exit 1; }
  echo "Updated grant $GRANT_ID -> $ROLE_JSON"
else
  CODE="$(http_code_body POST "/management/v1/users/${USER_ID}/grants" \
    -d "{\"projectId\":\"${PROJECT_ID}\",\"roleKeys\":[\"technologist\"]}")"
  [[ "$CODE" == "200" || "$CODE" == "201" ]] || {
    echo "Grant create failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }
  echo "Created grant with technologist"
fi

echo "WEB_CLIENT_ID=${CLIENT_ID}"
echo "OK"
