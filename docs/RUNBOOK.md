# RUNBOOK — self-host Zitadel (РФ)

Все чувствительные значения — в секретах. В командах ниже только **имена** переменных.

## Политика деплоя

**Деплой Compose на VPS — только из CI** (push в `master` после зелёных проверок, либо `workflow_dispatch`).

- Не деплоим с ноутбука (`ssh` / `rsync` / `docker compose` локально — не рабочий процесс).
- Локальный `~/.config/masterdoc-zitadel/env` **не требуется**.
- Секреты деплоя — только GitHub Actions secrets (см. [SECRETS.md](SECRETS.md)).

Unit-тесты на каждом PR **не** используют deploy secrets.

## 0. Секреты (до первого деплоя)

### GitHub Actions secrets

Settings → Secrets and variables → Actions — таблица в [SECRETS.md](SECRETS.md).

### На VPS (`/etc/masterdoc-zitadel/.env`, `chmod 600`)

Создай **один раз** на сервере (CI его не перезаписывает):

| Переменная | Примечание |
|------------|------------|
| `ZITADEL_DOMAIN` | FQDN без схемы |
| `ZITADEL_MASTERKEY` | ровно 32 символа, generate once, backup offline |
| `POSTGRES_ADMIN_PASSWORD` | сильный пароль |
| `ZITADEL_DATABASE_POSTGRES_DSN` | с тем же паролем |
| прочие | из [`deploy/.env.example`](../deploy/.env.example) |

```bash
tr -dc A-Za-z0-9 </dev/urandom | head -c 32
```

## 1. DNS и TLS

1. A-запись `${ZITADEL_DOMAIN}` → хост из `ZITADEL_DEPLOY_HOST`.
2. TLS: nginx перед Traefik (external-tls overlay) или Let's Encrypt — см. [`deploy/nginx.example.conf`](../deploy/nginx.example.conf) и upstream docs.

`ZITADEL_DOMAIN` / external port / `EXTERNALSECURE` должны совпадать с публичным URL.

## 2. Деплой Compose (CI)

Workflow: [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)

- Триггер: push в `master` (после CI) или ручной `workflow_dispatch`.
- Шаги: rsync `deploy/` → `/opt/masterdoc-zitadel/` → `docker compose … up -d --wait` по SSH.
- `.env` на сервере: symlink `/opt/masterdoc-zitadel/.env` → `/etc/masterdoc-zitadel/.env`.

Первый admin: Console after first start; смени дефолтный пароль.

## 3. Machine user + PAT (для Terraform)

В Console:

1. Service User → `terraform-masterdoc`.
2. Managers → Org Owner (bootstrap; потом сузить).
3. PAT → только в GitHub secret `ZITADEL_TOKEN` (не в чат).
4. `ZITADEL_ORG_ID` → secret.

## 4. Terraform platform

Пока: `terraform apply` — вручную с runner'а или позже отдельный CI job / `workflow_dispatch` с secrets `ZITADEL_*` и remote state.  
Не путать с деплоем Compose: platform apply — после того как IdP уже поднят CI.

Создаёт: project `masterdoc-toir`, 5 roles, OIDC native + web, login policy (no self-signup).

## 5. Verify

- Unit: каждый PR/push в CI (`./gradlew test`).
- Live: opt-in (`./gradlew liveTest`) — не в default CI.

## 6. Invite smoke (вручную в Console)

1. Organization клиента / demo.
2. Invite с ролью `engineer`.
3. JWT: `sub`, org, roles.

## 7. Бэкапы

- Dump Postgres volume `postgres-data`.
- Offline копия `ZITADEL_MASTERKEY`.
