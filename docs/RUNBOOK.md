# RUNBOOK — self-host Zitadel (РФ)

Все чувствительные значения — в **GitHub Secrets**. Сервер может смениться: меняешь `ZITADEL_DEPLOY_HOST` и гонишь Deploy заново.

## Политика деплоя

- Compose на VPS — **только CI** ([`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)).
- `.env` **собирается в CI из secrets** и копируется на VPS (`/etc/masterdoc-zitadel/.env`).
- Локальный env не нужен.
- Unit-тесты на PR secrets не используют.

## 0. Секреты

Список и генерация: [SECRETS.md](SECRETS.md).

Обязательно до Deploy: host, user, SSH key, domain, masterkey (32 chars), postgres password.

**Masterkey:** один раз сгенерировал → в secret → не ротируй без миграции данных (потеряешь доступ к encrypted-at-rest).

## 1. DNS и TLS

1. A-запись `${ZITADEL_DOMAIN}` → текущий `ZITADEL_DEPLOY_HOST`.
2. TLS: nginx перед Traefik или Let's Encrypt — [`deploy/nginx.example.conf`](../deploy/nginx.example.conf).

## 2. Деплой

Actions → **Deploy** → Run workflow (или push в `deploy/**`).

CI: verify secrets → rsync `deploy/` → записать `.env` из secrets → `docker compose up -d --wait`.

Первый admin: Console; смени пароль.

## 3. Смена VPS

1. Подними Docker на новом хосте, перенеси volume Postgres при необходимости.
2. Обнови secret `ZITADEL_DEPLOY_HOST` (и DNS).
3. Запусти Deploy.
4. Masterkey / postgres password в secrets **те же**, если данные те же.

## 4. Machine user + PAT

Console → service user `terraform-masterdoc` → PAT → secrets `ZITADEL_TOKEN` / `ZITADEL_ORG_ID`.

## 5. Terraform platform

Отдельный apply (позже CI); secrets `ZITADEL_DOMAIN` / `TOKEN` / `ORG_ID`.

## 6. Verify / invite smoke

Unit в CI; live и invite — по Console / opt-in.

## 7. Бэкапы

- Dump Postgres volume.
- Offline копия `ZITADEL_MASTERKEY` (из password manager / того же secret backup).
