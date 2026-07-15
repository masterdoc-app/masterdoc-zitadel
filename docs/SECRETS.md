# Checklist: secrets (человек)

**Политика:** деплой Compose на VPS — **только из GitHub Actions**. Локальный env для деплоя **не нужен**.

Значения **не** присылай в чат.

## GitHub → `AntonButov/masterdoc-zitadel` → Settings → Secrets → Actions

Обязательны для deploy workflow:

| Secret | Назначение |
|--------|------------|
| `ZITADEL_DEPLOY_HOST` | IP/host RU VPS (не коммитить) |
| `ZITADEL_DEPLOY_USER` | SSH user |
| `ZITADEL_SSH_PRIVATE_KEY` | private key целиком |

Позже (terraform apply / live — отдельный workflow или dispatch):

| Secret | Когда |
|--------|--------|
| `ZITADEL_DOMAIN` | DNS готов |
| `ZITADEL_TOKEN` | после machine user PAT |
| `ZITADEL_ORG_ID` | после bootstrap Console |

## На VPS (один раз, руками или bootstrap)

`/etc/masterdoc-zitadel/.env` (`chmod 600`) — **не** в git и не обязательно в GitHub:

- [ ] `ZITADEL_MASTERKEY` (32 chars, offline backup)
- [ ] `POSTGRES_ADMIN_PASSWORD` + DSN sync
- [ ] `ZITADEL_DOMAIN` matches DNS

CI копирует только `deploy/*.yml` (+ nginx example); `.env` на сервере уже должен лежать.

Подробности: [RUNBOOK.md](RUNBOOK.md).
