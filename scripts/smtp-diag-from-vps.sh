#!/usr/bin/env bash
# Probe SMTP reachability from the Zitadel VPS (SSH).
# Requires: ZITADEL_DEPLOY_HOST, ZITADEL_DEPLOY_USER, ZITADEL_SSH_PRIVATE_KEY
# Optional: SMTP_HOST (default mail.antonbutov.com)
set -euo pipefail

HOST="${ZITADEL_DEPLOY_HOST:?}"
USER_NAME="${ZITADEL_DEPLOY_USER:?}"
SSH_PRIVATE_KEY="${ZITADEL_SSH_PRIVATE_KEY:?}"
SMTP_HOST="${SMTP_HOST:-mail.antonbutov.com}"

mkdir -p ~/.ssh && chmod 700 ~/.ssh
printf '%s\n' "$SSH_PRIVATE_KEY" > ~/.ssh/deploy_key
chmod 600 ~/.ssh/deploy_key
ssh-keyscan -H "$HOST" >> ~/.ssh/known_hosts 2>/dev/null

echo "==> Zitadel VPS egress + SMTP ports ${SMTP_HOST}"
ssh -i ~/.ssh/deploy_key -o StrictHostKeyChecking=yes "${USER_NAME}@${HOST}" \
  SMTP_HOST="$SMTP_HOST" 'bash -s' <<'REMOTE'
set -euo pipefail
echo -n "egress_ip="
curl -4 -sS --max-time 5 ifconfig.me || curl -4 -sS --max-time 5 icanhazip.com || echo unknown
echo
for port in 587 465 25; do
  if nc -zv -w 5 "$SMTP_HOST" "$port" 2>&1; then
    echo "port_${port}=open"
  else
    echo "port_${port}=closed_or_filtered"
  fi
done
echo "==> STARTTLS handshake :587"
timeout 10 openssl s_client -connect "${SMTP_HOST}:587" -starttls smtp -servername "$SMTP_HOST" </dev/null 2>&1 | head -25 || true
REMOTE

echo "OK"
