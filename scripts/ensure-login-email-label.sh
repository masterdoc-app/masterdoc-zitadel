#!/usr/bin/env bash
# Login UI v2: ask for email only (label/copy), not "username or email".
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
API="https://${DOMAIN}"

admin_curl() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -X "$method" "${API}${path}" "$@"
}

BODY="$(python3 - <<'PY'
import json
print(json.dumps({
  "instance": True,
  "locale": "ru",
  "translations": {
    "loginname": {
      "description": "Введите электронную почту.",
      "labels": {
        "loginname": "Электронная почта",
        "username": "Электронная почта",
        "usernameOrEmail": "Электронная почта",
        "usernameOrPhoneNumber": "Электронная почта",
      },
    },
  },
}, ensure_ascii=False))
PY
)"

echo "==> Set hosted login translations (email-only labels, ru)"
CODE="$(admin_curl PUT /v2/settings/hosted_login_translation -d "$BODY")"
if [[ "$CODE" != "200" ]]; then
  if ! grep -qiE 'not been changed|не была изменен|не изменен|NO_CHANGES|AlreadyExists' /tmp/zitadel-body.json; then
    echo "SetHostedLoginTranslation failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  fi
  echo "OK (unchanged)"
else
  echo "OK response=$(cat /tmp/zitadel-body.json | head -c 200)"
fi

echo "==> Verify get (instance, ru, ignore_inheritance=true)"
CODE="$(curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/json" \
  "${API}/v2/settings/hosted_login_translation?locale=ru&level=LEVEL_INSTANCE&ignoreInheritance=true")"
# Some versions use query: instance=true
if [[ "$CODE" != "200" ]]; then
  CODE="$(curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json" \
    "${API}/v2/settings/hosted_login_translation?locale=ru&instance=true&ignoreInheritance=true")"
fi
if [[ "$CODE" == "200" ]]; then
  python3 - <<'PY'
import json
d=json.load(open("/tmp/zitadel-body.json"))
t=d.get("translations") or d
# nested or flat
import pprint
s=json.dumps(t, ensure_ascii=False)
if "Электронная почта" in s:
  print("verified: email label present")
else:
  print("WARN: email label not found in:", s[:500])
PY
else
  echo "WARN: get translation HTTP=$CODE body=$(cat /tmp/zitadel-body.json | head -c 300)"
fi

echo "OK"
