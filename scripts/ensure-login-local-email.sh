#!/usr/bin/env bash
# Ensure login policies allow local email+password login and keep Default Redirect → app.
# Also (re)applies RU email-only labels for Login UI v2.
#
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN, ZITADEL_ORG_ID
# Optional: EXTRA_ORG_IDS, DEFAULT_REDIRECT_URI
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
PLATFORM_ORG_ID="${ZITADEL_ORG_ID:?}"
EXTRA_ORG_IDS="${EXTRA_ORG_IDS:-}"
export DEFAULT_REDIRECT_URI="${DEFAULT_REDIRECT_URI:-https://app.fixaverse.ru/}"
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

INSTANCE_BODY="$(DEFAULT_REDIRECT_URI="$DEFAULT_REDIRECT_URI" python3 - <<'PY'
import json, os
print(json.dumps({
  "allowUsernamePassword": True,
  "allowRegister": False,
  "allowExternalIdp": False,
  "forceMfa": False,
  "forceMfaLocalOnly": False,
  "passwordlessType": "PASSWORDLESS_TYPE_NOT_ALLOWED",
  "hidePasswordReset": False,
  "ignoreUnknownUsernames": True,
  "defaultRedirectUri": os.environ["DEFAULT_REDIRECT_URI"],
  "passwordCheckLifetime": "864000s",
  "externalLoginCheckLifetime": "864000s",
  "mfaInitSkipLifetime": "2592000s",
  "secondFactorCheckLifetime": "86400s",
  "multiFactorCheckLifetime": "86400s",
  "allowDomainDiscovery": False,
  "disableLoginWithEmail": False,
  "disableLoginWithPhone": True,
}))
PY
)"

ORG_BODY="$(DEFAULT_REDIRECT_URI="$DEFAULT_REDIRECT_URI" python3 - <<'PY'
import json, os
print(json.dumps({
  "userLogin": True,
  "allowRegister": False,
  "allowExternalIdp": False,
  "forceMfa": False,
  "forceMfaLocalOnly": False,
  "passwordlessType": "PASSWORDLESS_TYPE_NOT_ALLOWED",
  "hidePasswordReset": False,
  "ignoreUnknownUsernames": True,
  "defaultRedirectUri": os.environ["DEFAULT_REDIRECT_URI"],
  "passwordCheckLifetime": "864000s",
  "externalLoginCheckLifetime": "864000s",
  "mfaInitSkipLifetime": "2592000s",
  "secondFactorCheckLifetime": "86400s",
  "multiFactorCheckLifetime": "86400s",
  "allowDomainDiscovery": False,
  "disableLoginWithEmail": False,
  "disableLoginWithPhone": True,
}))
PY
)"

ok_or_unchanged() {
  local code="$1" what="$2"
  if [[ "$code" == "200" || "$code" == "201" ]]; then
    echo "OK $what"
    return 0
  fi
  if grep -qiE 'not been changed|INSTANCE-|ORG-|не была изменен|не изменен|AlreadyExists|NO_CHANGES' /tmp/zitadel-body.json; then
    echo "OK $what (unchanged)"
    return 0
  fi
  echo "FAILED $what ($code): $(cat /tmp/zitadel-body.json)" >&2
  return 1
}

echo "==> Instance login policy (local email+password, redirect=${DEFAULT_REDIRECT_URI})"
CODE="$(admin_curl PUT /admin/v1/policies/login -d "$INSTANCE_BODY")"
ok_or_unchanged "$CODE" "instance" || exit 1

ensure_org() {
  local org_id="$1"
  echo "==> Org login policy org=$org_id (userLogin=true)"
  CODE="$(mgmt_curl "$org_id" PUT /management/v1/policies/login -d "$ORG_BODY")"
  if [[ "$CODE" != "200" ]]; then
    CODE="$(mgmt_curl "$org_id" POST /management/v1/policies/login -d "$ORG_BODY")"
  fi
  ok_or_unchanged "$CODE" "org=$org_id" || exit 1
}

ensure_org "$PLATFORM_ORG_ID"
for oid in $EXTRA_ORG_IDS; do
  [[ -n "$oid" ]] && ensure_org "$oid"
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -x "${SCRIPT_DIR}/ensure-login-email-label.sh" ]]; then
  echo "==> Email-only labels"
  "${SCRIPT_DIR}/ensure-login-email-label.sh"
fi

echo "OK"
