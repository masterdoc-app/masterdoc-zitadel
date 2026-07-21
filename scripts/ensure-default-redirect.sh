#!/usr/bin/env bash
# Set Default Redirect URI so invite / password flows land in the app, not Console.
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN
# Optional:
#   DEFAULT_REDIRECT_URI (default https://app.fixaverse.ru/)
#   ZITADEL_ORG_ID + EXTRA_ORG_IDS — also set on org login policies
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
export DEFAULT_REDIRECT_URI="${DEFAULT_REDIRECT_URI:-https://app.fixaverse.ru/}"
PLATFORM_ORG_ID="${ZITADEL_ORG_ID:-}"
EXTRA_ORG_IDS="${EXTRA_ORG_IDS:-}"
API="https://${DOMAIN}"

admin_curl() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -X "$method" "${API}${path}" "$@"
}

mgmt_curl() {
  local org_id="$1" method="$2" path="$3"
  shift 3
  curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${org_id}" \
    -X "$method" "${API}${path}" "$@"
}

build_body_from_policy() {
  # Merge desired defaultRedirectUri into existing policy JSON (Admin or Management shape).
  DEFAULT_REDIRECT_URI="$DEFAULT_REDIRECT_URI" python3 - <<'PY'
import json, os
raw = json.load(open("/tmp/zitadel-body.json"))
p = raw.get("policy") or raw
uri = os.environ["DEFAULT_REDIRECT_URI"]
# Prefer keys present in current policy; Admin uses allowUsernamePassword, Mgmt often userLogin.
body = {
  "allowRegister": bool(p.get("allowRegister", False)),
  "allowExternalIdp": bool(p.get("allowExternalIdp", False)),
  "forceMfa": bool(p.get("forceMfa", False)),
  "forceMfaLocalOnly": bool(p.get("forceMfaLocalOnly", False)),
  "passwordlessType": p.get("passwordlessType") or "PASSWORDLESS_TYPE_NOT_ALLOWED",
  "hidePasswordReset": bool(p.get("hidePasswordReset", False)),
  "ignoreUnknownUsernames": bool(p.get("ignoreUnknownUsernames", True)),
  "defaultRedirectUri": uri,
  "passwordCheckLifetime": p.get("passwordCheckLifetime") or "864000s",
  "externalLoginCheckLifetime": p.get("externalLoginCheckLifetime") or "864000s",
  "mfaInitSkipLifetime": p.get("mfaInitSkipLifetime") or "2592000s",
  "secondFactorCheckLifetime": p.get("secondFactorCheckLifetime") or "86400s",
  "multiFactorCheckLifetime": p.get("multiFactorCheckLifetime") or "86400s",
  "allowDomainDiscovery": bool(p.get("allowDomainDiscovery", False)),
  "disableLoginWithEmail": bool(p.get("disableLoginWithEmail", False)),
  "disableLoginWithPhone": bool(p.get("disableLoginWithPhone", True)),
}
if "allowUsernamePassword" in p or "userLogin" not in p:
  body["allowUsernamePassword"] = bool(p.get("allowUsernamePassword", p.get("userLogin", True)))
else:
  body["userLogin"] = bool(p.get("userLogin", True))
print(json.dumps(body))
PY
}

current_redirect() {
  python3 -c 'import json; p=json.load(open("/tmp/zitadel-body.json")).get("policy") or {}; print(p.get("defaultRedirectUri") or "")'
}

ensure_instance() {
  echo "==> Instance default login policy redirect → ${DEFAULT_REDIRECT_URI}"
  CODE="$(admin_curl GET /admin/v1/policies/login)"
  [[ "$CODE" == "200" ]] || {
    echo "Get instance login policy failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }
  CUR="$(current_redirect)"
  echo "current defaultRedirectUri=${CUR:-<empty>}"
  if [[ "$CUR" == "$DEFAULT_REDIRECT_URI" ]]; then
    echo "OK instance (already set)"
    return 0
  fi
  BODY="$(build_body_from_policy)"
  CODE="$(admin_curl PUT /admin/v1/policies/login -d "$BODY")"
  if [[ "$CODE" != "200" ]]; then
    if grep -qiE 'not been changed|INSTANCE-|не была изменен|не изменен' /tmp/zitadel-body.json; then
      echo "OK instance (unchanged)"
      return 0
    fi
    echo "Update instance login policy failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  fi
  CODE="$(admin_curl GET /admin/v1/policies/login)"
  [[ "$CODE" == "200" ]] || {
    echo "Verify get failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }
  CUR="$(current_redirect)"
  [[ "$CUR" == "$DEFAULT_REDIRECT_URI" ]] || {
    echo "Verify failed: got defaultRedirectUri=${CUR}" >&2
    exit 1
  }
  echo "OK instance"
}

ensure_org() {
  local org_id="$1"
  echo "==> Org login policy org=$org_id redirect → ${DEFAULT_REDIRECT_URI}"
  CODE="$(mgmt_curl "$org_id" GET /management/v1/policies/login)"
  [[ "$CODE" == "200" ]] || {
    echo "Get org login policy failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  }
  CUR="$(current_redirect)"
  echo "current defaultRedirectUri=${CUR:-<empty>}"
  if [[ "$CUR" == "$DEFAULT_REDIRECT_URI" ]]; then
    echo "OK org=$org_id (already set)"
    return 0
  fi
  BODY="$(build_body_from_policy)"
  # Management API uses userLogin, not allowUsernamePassword
  BODY="$(DEFAULT_REDIRECT_URI="$DEFAULT_REDIRECT_URI" python3 -c '
import json, os
p = json.load(open("/tmp/zitadel-body.json")).get("policy") or {}
uri = os.environ["DEFAULT_REDIRECT_URI"]
print(json.dumps({
  "userLogin": bool(p.get("userLogin", True)),
  "allowRegister": bool(p.get("allowRegister", False)),
  "allowExternalIdp": bool(p.get("allowExternalIdp", False)),
  "forceMfa": bool(p.get("forceMfa", False)),
  "forceMfaLocalOnly": bool(p.get("forceMfaLocalOnly", False)),
  "passwordlessType": p.get("passwordlessType") or "PASSWORDLESS_TYPE_NOT_ALLOWED",
  "hidePasswordReset": False,
  "ignoreUnknownUsernames": bool(p.get("ignoreUnknownUsernames", True)),
  "defaultRedirectUri": uri,
  "passwordCheckLifetime": "864000s",
  "externalLoginCheckLifetime": "864000s",
  "mfaInitSkipLifetime": "2592000s",
  "secondFactorCheckLifetime": "86400s",
  "multiFactorCheckLifetime": "86400s",
  "allowDomainDiscovery": bool(p.get("allowDomainDiscovery", False)),
  "disableLoginWithEmail": bool(p.get("disableLoginWithEmail", False)),
  "disableLoginWithPhone": bool(p.get("disableLoginWithPhone", True)),
}))
')"
  CODE="$(mgmt_curl "$org_id" PUT /management/v1/policies/login -d "$BODY")"
  if [[ "$CODE" != "200" ]]; then
    CODE="$(mgmt_curl "$org_id" POST /management/v1/policies/login -d "$BODY")"
  fi
  if [[ "$CODE" != "200" && "$CODE" != "201" ]]; then
    if ! grep -qiE 'not been changed|не была изменен|не изменен|AlreadyExists' /tmp/zitadel-body.json; then
      echo "Set org login policy failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
      exit 1
    fi
  fi
  echo "OK org=$org_id"
}

ensure_instance
if [[ -n "$PLATFORM_ORG_ID" ]]; then
  ensure_org "$PLATFORM_ORG_ID"
fi
for oid in $EXTRA_ORG_IDS; do
  [[ -n "$oid" ]] && ensure_org "$oid"
done
echo "DEFAULT_REDIRECT_URI=${DEFAULT_REDIRECT_URI}"
echo "OK"
