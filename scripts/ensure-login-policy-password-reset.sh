#!/usr/bin/env bash
# Ensure login policy shows password reset (forgot password) on password step.
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN, ZITADEL_ORG_ID
# Optional: EXTRA_ORG_IDS (space-separated)
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
PLATFORM_ORG_ID="${ZITADEL_ORG_ID:?}"
EXTRA_ORG_IDS="${EXTRA_ORG_IDS:-}"
API="https://${DOMAIN}"

ensure_org() {
  local org_id="$1"
  echo "==> Login policy org=$org_id (hidePasswordReset=false)"
  CODE="$(curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${org_id}" \
    -X GET "${API}/management/v1/policies/login")"
  if [[ "$CODE" != "200" ]]; then
    echo "Get login policy failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  fi
  HIDE="$(python3 -c 'import json; p=json.load(open("/tmp/zitadel-body.json")).get("policy") or {}; print(str(p.get("hidePasswordReset", False)).lower())')"
  echo "hidePasswordReset=$HIDE"
  if [[ "$HIDE" == "false" ]]; then
    echo "OK org=$org_id (already shows password reset)"
    return 0
  fi
  # Management API expects seconds-based durations (e.g. 864000s), not Go "240h0m0s".
  BODY='{
    "userLogin": true,
    "allowRegister": false,
    "allowExternalIdp": false,
    "forceMfa": false,
    "forceMfaLocalOnly": false,
    "passwordlessType": "PASSWORDLESS_TYPE_NOT_ALLOWED",
    "hidePasswordReset": false,
    "ignoreUnknownUsernames": true,
    "defaultRedirectUri": "",
    "passwordCheckLifetime": "864000s",
    "externalLoginCheckLifetime": "864000s",
    "mfaInitSkipLifetime": "2592000s",
    "secondFactorCheckLifetime": "86400s",
    "multiFactorCheckLifetime": "86400s",
    "allowDomainDiscovery": false,
    "disableLoginWithEmail": false,
    "disableLoginWithPhone": true
  }'
  # Prefer update; if no custom policy, add
  CODE="$(curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${org_id}" \
    -X PUT "${API}/management/v1/policies/login" -d "$BODY")"
  if [[ "$CODE" != "200" ]]; then
    CODE="$(curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -H "x-zitadel-orgid: ${org_id}" \
      -X POST "${API}/management/v1/policies/login" -d "$BODY")"
  fi
  if [[ "$CODE" != "200" && "$CODE" != "201" ]]; then
    if ! grep -qiE 'not been changed|не измен|AlreadyExists' /tmp/zitadel-body.json; then
      echo "Set login policy failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
      exit 1
    fi
  fi
  echo "OK org=$org_id"
}

ensure_org "$PLATFORM_ORG_ID"
for oid in $EXTRA_ORG_IDS; do
  [[ -n "$oid" ]] && ensure_org "$oid"
done
echo "OK"
