#!/usr/bin/env bash
# From Zitadel VPS: probe SMTP from inside the zitadel-api container.
set -euo pipefail

HOST="${ZITADEL_DEPLOY_HOST:?}"
USER_NAME="${ZITADEL_DEPLOY_USER:?}"
SSH_PRIVATE_KEY="${ZITADEL_SSH_PRIVATE_KEY:?}"
SMTP_HOST="${SMTP_HOST:-mail.antonbutov.com}"

mkdir -p ~/.ssh && chmod 700 ~/.ssh
printf '%s\n' "$SSH_PRIVATE_KEY" > ~/.ssh/deploy_key
chmod 600 ~/.ssh/deploy_key
ssh-keyscan -H "$HOST" >> ~/.ssh/known_hosts 2>/dev/null

ssh -i ~/.ssh/deploy_key -o StrictHostKeyChecking=yes "${USER_NAME}@${HOST}" \
  SMTP_HOST="$SMTP_HOST" 'bash -s' <<'REMOTE'
set -euo pipefail
cd /opt/masterdoc-zitadel 2>/dev/null || cd /etc/masterdoc-zitadel/.. || true
CID="$(docker ps --filter name=zitadel-api --format '{{.ID}}' | head -1)"
echo "zitadel_api_container=$CID"
if [[ -z "$CID" ]]; then
  docker ps --format '{{.Names}}' | head -20
  exit 1
fi
echo "==> DNS inside container"
docker exec "$CID" getent hosts "$SMTP_HOST" || docker exec "$CID" nslookup "$SMTP_HOST" || true
echo "==> TCP :587 inside container"
docker exec "$CID" sh -c "command -v nc >/dev/null && nc -zv -w 5 $SMTP_HOST 587 || (echo > /dev/tcp/$SMTP_HOST/587 && echo tcp_ok) || echo tcp_fail"
echo "==> Recent zitadel logs (smtp/tls/email)"
docker logs --tail 200 "$CID" 2>&1 | grep -iE 'smtp|tls|email|EMAIL-|certificate|x509' | tail -40 || true
REMOTE
