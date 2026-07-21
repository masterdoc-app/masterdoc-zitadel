# Checklist: secrets (человек)

**Политика:**
- деплой Compose — **только из GitHub Actions**;
- **все чувствительные данные — в GitHub Secrets** (хост тоже), потому что сервер может смениться;
- CI при каждом деплое собирает `.env` из secrets и кладёт на текущий VPS;
- локальный env **не нужен**.

Значения **не** присылай в чат.

## GitHub → `AntonButov/masterdoc-zitadel` → Settings → Secrets → Actions

### Обязательны для Deploy

| Secret | Назначение | Как сгенерировать |
|--------|------------|-------------------|
| `ZITADEL_DEPLOY_HOST` | IP/host текущего VPS | — |
| `ZITADEL_DEPLOY_USER` | SSH user (`root` / …) | — |
| `ZITADEL_SSH_PRIVATE_KEY` | private key целиком | ключ с доступом на VPS |
| `ZITADEL_DOMAIN` | FQDN IdP без `https://` | DNS A → этот host |
| `ZITADEL_MASTERKEY` | ровно **32** символа; **не менять** после первого успешного старта | `tr -dc A-Za-z0-9 </dev/urandom \| head -c 32` |
| `POSTGRES_ADMIN_PASSWORD` | пароль Postgres; DSN соберёт CI | сильный пароль |

Смена сервера: обнови `ZITADEL_DEPLOY_HOST` (+ DNS при необходимости) и перезапусти Deploy. Masterkey/пароль БД **не** пересоздавай, если переносишь тот же volume данных.

### Позже (Terraform / live)

| Secret | Когда |
|--------|--------|
| `ZITADEL_TOKEN` | после machine user PAT |
| `ZITADEL_ORG_ID` | после bootstrap Console |
| `ZITADEL_SMTP_PASSWORD` | SMTP пароль для `mail@antonbutov.com` на `mail.antonbutov.com:587` (workflow **Ensure SMTP + Demo Org**) |

## Что не лежит «только на диске сервера»

Файл `/etc/masterdoc-zitadel/.env` создаёт **CI из secrets** при деплое. Source of truth — GitHub Secrets, не ручной файл на VPS.

Подробности: [RUNBOOK.md](RUNBOOK.md).
