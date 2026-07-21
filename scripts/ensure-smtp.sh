#!/usr/bin/env bash
# Idempotent SMTP email provider for self-hosted Zitadel (Admin API).
# Existing instance: DEFAULTINSTANCE env is ignored — configure via API.
#
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN, ZITADEL_SMTP_PASSWORD
# Optional:
#   ZITADEL_SMTP_HOST (default mail.antonbutov.com:587)
#   ZITADEL_SMTP_USER / ZITADEL_SMTP_FROM (default mail@antonbutov.com)
#   ZITADEL_SMTP_FROM_NAME (default Fixaverse)
#   ZITADEL_SMTP_TLS (default true)
#   ZITADEL_SMTP_TEST_TO (default = FROM; empty skips test mail)
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
SMTP_PASSWORD="${ZITADEL_SMTP_PASSWORD:?}"
SMTP_HOST="${ZITADEL_SMTP_HOST:-mail.antonbutov.com:587}"
SMTP_USER="${ZITADEL_SMTP_USER:-mail@antonbutov.com}"
SMTP_FROM="${ZITADEL_SMTP_FROM:-mail@antonbutov.com}"
SMTP_FROM_NAME="${ZITADEL_SMTP_FROM_NAME:-Fixaverse}"
SMTP_TLS="${ZITADEL_SMTP_TLS:-true}"
SMTP_TEST_TO="${ZITADEL_SMTP_TEST_TO:-$SMTP_FROM}"
API="https://${DOMAIN}"
DESC="mail.antonbutov.com"

admin_curl() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o /tmp/zitadel-admin-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -X "$method" "${API}${path}" "$@"
}

echo "==> Domain policy: allow From outside instance domain"
CODE="$(admin_curl GET /admin/v1/policies/domain)"
if [[ "$CODE" != "200" ]]; then
  echo "GetDomainPolicy failed ($CODE): $(cat /tmp/zitadel-admin-body.json)" >&2
  exit 1
fi
POLICY_JSON="$(python3 - <<'PY'
import json
p = json.load(open("/tmp/zitadel-admin-body.json")).get("policy") or {}
print(json.dumps({
  "userLoginMustBeDomain": bool(p.get("userLoginMustBeDomain", False)),
  "validateOrgDomains": bool(p.get("validateOrgDomains", False)),
  "smtpSenderAddressMatchesInstanceDomain": False,
}))
PY
)"
CODE="$(admin_curl PUT /admin/v1/policies/domain -d "$POLICY_JSON")"
if [[ "$CODE" != "200" ]]; then
  # already set / no change is ok for some versions
  if ! grep -qiE 'not been changed|AlreadyExists|NO_CHANGES' /tmp/zitadel-admin-body.json; then
    echo "UpdateDomainPolicy failed ($CODE): $(cat /tmp/zitadel-admin-body.json)" >&2
    exit 1
  fi
fi
echo "Domain policy OK (smtpSenderAddressMatchesInstanceDomain=false)"

echo "==> List email providers"
CODE="$(admin_curl POST /admin/v1/email/_search -d '{}')"
[[ "$CODE" == "200" ]] || {
  echo "ListEmailProviders failed ($CODE): $(cat /tmp/zitadel-admin-body.json)" >&2
  exit 1
}

PROVIDER_ID="$(SMTP_HOST="$SMTP_HOST" SMTP_FROM="$SMTP_FROM" python3 - <<'PY'
import json, os
host = os.environ["SMTP_HOST"]
from_addr = os.environ["SMTP_FROM"]
rows = json.load(open("/tmp/zitadel-admin-body.json")).get("result") or []
for r in rows:
    smtp = r.get("smtp") or {}
    if smtp.get("host") == host or smtp.get("senderAddress") == from_addr or r.get("description") == "mail.antonbutov.com":
        print(r.get("id") or "")
        break
PY
)"

SMTP_BODY="$(SMTP_HOST="$SMTP_HOST" SMTP_USER="$SMTP_USER" SMTP_FROM="$SMTP_FROM" \
  SMTP_FROM_NAME="$SMTP_FROM_NAME" SMTP_TLS="$SMTP_TLS" SMTP_PASSWORD="$SMTP_PASSWORD" DESC="$DESC" \
  python3 - <<'PY'
import json, os
tls = os.environ["SMTP_TLS"].lower() in ("1", "true", "yes")
print(json.dumps({
  "senderAddress": os.environ["SMTP_FROM"],
  "senderName": os.environ["SMTP_FROM_NAME"],
  "tls": tls,
  "host": os.environ["SMTP_HOST"],
  "user": os.environ["SMTP_USER"],
  "description": os.environ["DESC"],
  "plain": {"password": os.environ["SMTP_PASSWORD"]},
}))
PY
)"

if [[ -n "$PROVIDER_ID" ]]; then
  echo "Updating provider $PROVIDER_ID"
  CODE="$(admin_curl PUT "/admin/v1/email/smtp/${PROVIDER_ID}" -d "$SMTP_BODY")"
  [[ "$CODE" == "200" ]] || {
    echo "UpdateEmailProviderSMTP failed ($CODE): $(cat /tmp/zitadel-admin-body.json)" >&2
    exit 1
  }
else
  echo "Creating SMTP provider"
  CODE="$(admin_curl POST /admin/v1/email/smtp -d "$SMTP_BODY")"
  [[ "$CODE" == "200" || "$CODE" == "201" ]] || {
    echo "AddEmailProviderSMTP failed ($CODE): $(cat /tmp/zitadel-admin-body.json)" >&2
    exit 1
  }
  PROVIDER_ID="$(python3 -c 'import json; print(json.load(open("/tmp/zitadel-admin-body.json")).get("id",""))')"
  [[ -n "$PROVIDER_ID" ]] || {
    echo "No provider id in create response: $(cat /tmp/zitadel-admin-body.json)" >&2
    exit 1
  }
fi
echo "PROVIDER_ID=$PROVIDER_ID"

echo "==> Activate provider"
CODE="$(admin_curl POST "/admin/v1/email/${PROVIDER_ID}/_activate" -d '{}')"
if [[ "$CODE" != "200" ]]; then
  if ! grep -qiE 'already|active|not been changed' /tmp/zitadel-admin-body.json; then
    echo "ActivateEmailProvider failed ($CODE): $(cat /tmp/zitadel-admin-body.json)" >&2
    exit 1
  fi
fi
echo "Provider active"

if [[ -n "$SMTP_TEST_TO" ]]; then
  echo "==> Test SMTP → ${SMTP_TEST_TO}"
  TEST_BODY="$(SMTP_TEST_TO="$SMTP_TEST_TO" python3 -c 'import json,os; print(json.dumps({"receiverAddress": os.environ["SMTP_TEST_TO"]}))')"
  CODE="$(admin_curl POST "/admin/v1/email/smtp/${PROVIDER_ID}/_test" -d "$TEST_BODY")"
  [[ "$CODE" == "200" ]] || {
    echo "TestEmailProviderSMTPById failed ($CODE): $(cat /tmp/zitadel-admin-body.json)" >&2
    exit 1
  }
  echo "Test mail accepted by SMTP"
fi

echo "OK"
