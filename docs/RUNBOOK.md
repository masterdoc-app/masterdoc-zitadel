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
2. TLS: nginx на `:80`/`:443`, Traefik только на `127.0.0.1:18080` — [`deploy/nginx.example.conf`](../deploy/nginx.example.conf).

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

Для gateway admin (`/admin/users*`): PAT должен уметь в **клиентских org** (не только platform):

- читать/создавать пользователей и grants (invite + list)
- **удалять** invited users (`user.delete` / роль уровня Org User Manager или выше) — иначе revoke вернёт 502/403

Platform `ZITADEL_ORG_ID` в secrets — org владельца продукта для Terraform; tenant для admin API берётся из JWT `resourceowner` / `org:id`.

## 5. Terraform platform

Workflow **Terraform Apply** (`workflow_dispatch`) — project `masterdoc-toir`, feature keys (`board`, `charts`, `copilot`, `equipment`, `admin`), OIDC apps (`masterdoc-kmp-native`, `masterdoc-kmp-web`), login policy (no self-signup).

Secrets: `ZITADEL_DOMAIN`, `ZITADEL_TOKEN`, `ZITADEL_ORG_ID`.

После apply — `native_client_id` / `web_client_id` в outputs workflow; положить `web_client_id` в client-app secret `FIXAVERSE_OIDC_WEB_CLIENT_ID`.

Для точечного патча (feature keys + redirect `app.fixaverse.ru` + user grant): workflow **Ensure Technologist Platform**.

## 6. SMTP + demo org invite

Workflow **Ensure SMTP + Demo Org** (`workflow_dispatch`):

1. Admin API: domain policy (`smtpSenderAddressMatchesInstanceDomain=false`), SMTP provider `mail.antonbutov.com:587` / From `mail@antonbutov.com`, activate + test mail.
2. Создаёт (или переиспользует) org **Fixaverse Demo**, project grant `masterdoc-toir`, invite на email (default `mail@antonbutov.com`).

Secret: `ZITADEL_SMTP_PASSWORD`.

Demo org id (reference): `382715225649971203`.

## 7. Smoke org (не Demo)

Отдельная клиентская org для agent / UI smoke — **не** путать с Demo.

Workflow **Ensure Smoke Org** (`workflow_dispatch`):

1. Создаёт (или переиспользует) org **Fixaverse Smoke**, project grant `masterdoc-toir` (все feature keys).
2. Invite на `mail+smoke@antonbutov.com` (Anton Butov) — плюс-адресация в тот же inbox; bare `mail@antonbutov.com` занят Demo (emails instance-unique).
3. Login policy (password reset) + `ORG_USER_MANAGER` для mgmt PAT на этой org.

Smoke org id (после первого ensure): `383177088934346755`.

Secrets: те же `ZITADEL_DOMAIN` / `ZITADEL_TOKEN` / `ZITADEL_ORG_ID` (SMTP уже из §6).

## 8. Verify / invite smoke

Unit в CI; live и invite — по Console / opt-in, tenant = **Fixaverse Smoke**.

## 9. Бэкапы

- Dump Postgres volume.
- Offline копия `ZITADEL_MASTERKEY` (из password manager / того же secret backup).
