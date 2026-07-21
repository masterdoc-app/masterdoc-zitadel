#!/usr/bin/env bash
# Instance branding for invite emails: Russian + Fixaverse (not ZITADEL).
#
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN
# Optional: ZITADEL_ORG_ID (unused; instance-level Admin API)
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
API="https://${DOMAIN}"
APP_NAME="${BRAND_APP_NAME:-Fixaverse}"

admin_curl() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o /tmp/zitadel-admin-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -X "$method" "${API}${path}" "$@"
}

echo "==> Default language → ru"
CODE="$(admin_curl PUT /admin/v1/languages/default/ru -d '{}')"
if [[ "$CODE" != "200" ]]; then
  echo "SetDefaultLanguage failed ($CODE): $(cat /tmp/zitadel-admin-body.json)" >&2
  exit 1
fi
echo "Default language set to ru"

set_invite_text() {
  local lang="$1"
  local body="$2"
  echo "==> Invite message texts ($lang)"
  CODE="$(admin_curl PUT "/admin/v1/text/message/invite_user/${lang}" -d "$body")"
  [[ "$CODE" == "200" ]] || {
    echo "SetDefaultInviteUserMessageText ($lang) failed ($CODE): $(cat /tmp/zitadel-admin-body.json)" >&2
    exit 1
  }
  echo "OK $lang"
}

# Hardcode Fixaverse so emails stay branded even if ApplicationName defaults to ZITADEL.
RU_BODY="$(APP_NAME="$APP_NAME" python3 - <<'PY'
import json, os
a = os.environ["APP_NAME"]
print(json.dumps({
  "title": f"Приглашение в {a}",
  "preHeader": f"Приглашение в {a}",
  "subject": f"Приглашение в {a}",
  "greeting": "Здравствуйте, {{.DisplayName}},",
  "text": (
    f"Вас пригласили в {a}. Нажмите кнопку ниже, чтобы завершить приглашение "
    "и задать пароль. Если вы не ожидали это письмо — просто проигнорируйте его."
  ),
  "buttonText": "Принять приглашение",
  "footerText": a,
}, ensure_ascii=False))
PY
)"

EN_BODY="$(APP_NAME="$APP_NAME" python3 - <<'PY'
import json, os
a = os.environ["APP_NAME"]
print(json.dumps({
  "title": f"Invitation to {a}",
  "preHeader": f"Invitation to {a}",
  "subject": f"Invitation to {a}",
  "greeting": "Hello {{.DisplayName}},",
  "text": (
    f"You have been invited to {a}. Click the button below to finish the invite "
    "and set your password. If you did not expect this email, you can ignore it."
  ),
  "buttonText": "Accept invite",
  "footerText": a,
}))
PY
)"

set_invite_text ru "$RU_BODY"
set_invite_text en "$EN_BODY"

echo "BRAND_APP_NAME=${APP_NAME}"
echo "OK"
