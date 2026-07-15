# Checklist: secrets (человек)

Скопируй и отмечай. Значения **не** присылай в чат.

## Локально

- [ ] `~/.config/masterdoc-zitadel/env` создан, `chmod 600`
- [ ] `ZITADEL_DEPLOY_HOST` = IP RU backend VPS
- [ ] `ZITADEL_DEPLOY_USER`
- [ ] `ZITADEL_SSH_KEY_PATH`
- [ ] (позже) `ZITADEL_DOMAIN`
- [ ] (позже) `ZITADEL_TOKEN` / `ZITADEL_ORG_ID`

## GitHub → `AntonButov/masterdoc-zitadel` → Settings → Secrets → Actions

- [ ] `ZITADEL_DEPLOY_HOST`
- [ ] `ZITADEL_DEPLOY_USER`
- [ ] `ZITADEL_SSH_PRIVATE_KEY`
- [ ] (позже) `ZITADEL_DOMAIN`
- [ ] (позже) `ZITADEL_TOKEN`
- [ ] (позже) `ZITADEL_ORG_ID`

## На VPS `/etc/masterdoc-zitadel/.env`

- [ ] `ZITADEL_MASTERKEY` (32 chars, offline backup)
- [ ] `POSTGRES_ADMIN_PASSWORD` + DSN sync
- [ ] `ZITADEL_DOMAIN` matches DNS

Подробности: [RUNBOOK.md](RUNBOOK.md) §0.
