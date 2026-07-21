#!/usr/bin/env bash
# Set instance default password complexity: min length only (no case/digit/symbol).
# Requires: ZITADEL_DOMAIN, ZITADEL_TOKEN
# Optional: MIN_LENGTH (default 8)
set -euo pipefail

DOMAIN="${ZITADEL_DOMAIN:?}"
TOKEN="${ZITADEL_TOKEN:?}"
export MIN_LENGTH="${MIN_LENGTH:-8}"
API="https://${DOMAIN}"

BODY="$(MIN_LENGTH="$MIN_LENGTH" python3 -c '
import json, os
print(json.dumps({
  "minLength": os.environ["MIN_LENGTH"],
  "hasUppercase": False,
  "hasLowercase": False,
  "hasNumber": False,
  "hasSymbol": False,
}))
')"

echo "==> GET current password complexity"
CODE="$(curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${API}/admin/v1/policies/password/complexity")"
[[ "$CODE" == "200" ]] || {
  echo "Get password complexity failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
}
python3 - <<'PY'
import json
p = json.load(open("/tmp/zitadel-body.json")).get("policy") or {}
print(
  "current:",
  f"minLength={p.get('minLength')}",
  f"upper={p.get('hasUppercase')}",
  f"lower={p.get('hasLowercase')}",
  f"number={p.get('hasNumber')}",
  f"symbol={p.get('hasSymbol')}",
)
PY

echo "==> PUT password complexity (minLength=${MIN_LENGTH}, no other rules)"
CODE="$(curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -X PUT "${API}/admin/v1/policies/password/complexity" \
  -d "$BODY")"
if [[ "$CODE" != "200" ]]; then
  if grep -qiE 'not been changed|не измен' /tmp/zitadel-body.json; then
    echo "OK (unchanged)"
  else
    echo "Update password complexity failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
    exit 1
  fi
fi

CODE="$(curl -sS -o /tmp/zitadel-body.json -w '%{http_code}' \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${API}/admin/v1/policies/password/complexity")"
[[ "$CODE" == "200" ]] || {
  echo "Verify get failed ($CODE): $(cat /tmp/zitadel-body.json)" >&2
  exit 1
}
python3 - <<'PY'
import json, os, sys
p = json.load(open("/tmp/zitadel-body.json")).get("policy") or {}

def flag(key: str) -> bool:
    # Admin GET may omit false booleans
    return bool(p.get(key))

want_min = os.environ.get("MIN_LENGTH", "8")
ok = (
    str(p.get("minLength")) == want_min
    and not flag("hasUppercase")
    and not flag("hasLowercase")
    and not flag("hasNumber")
    and not flag("hasSymbol")
)
print(
    "verified:",
    f"minLength={p.get('minLength')}",
    f"upper={flag('hasUppercase')}",
    f"lower={flag('hasLowercase')}",
    f"number={flag('hasNumber')}",
    f"symbol={flag('hasSymbol')}",
)
sys.exit(0 if ok else 1)
PY

echo "OK"
