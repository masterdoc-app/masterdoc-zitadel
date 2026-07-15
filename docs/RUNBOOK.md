# RUNBOOK — self-host Zitadel (РФ)

Все чувствительные значения — в секретах. В командах ниже только **имена** переменных.

## 0. Секреты (сделай до деплоя)

### Локально (`~/.config/masterdoc-zitadel/env`, `chmod 600`)

```bash
export ZITADEL_DEPLOY_HOST="…"       # IP RU backend VPS (IdP Docker)
export ZITADEL_DEPLOY_USER="root"    # или deploy-user
export ZITADEL_SSH_KEY_PATH="$HOME/.ssh/…"

# после DNS:
export ZITADEL_DOMAIN="auth.example.com"   # FQDN без https://

# после machine user + PAT:
# export ZITADEL_TOKEN="…"
# export ZITADEL_ORG_ID="…"
```

`source ~/.config/masterdoc-zitadel/env`

### GitHub Actions secrets (после появления репо)

Settings → Secrets and variables → Actions:

| Secret | Когда |
|--------|--------|
| `ZITADEL_DEPLOY_HOST` | сразу |
| `ZITADEL_DEPLOY_USER` | сразу |
| `ZITADEL_SSH_PRIVATE_KEY` | сразу |
| `ZITADEL_DOMAIN` | когда есть DNS |
| `ZITADEL_TOKEN` | после PAT |
| `ZITADEL_ORG_ID` | после bootstrap Console |

Unit CI **не** читает эти secrets. Они для ручного deploy/apply и будущих opt-in workflow.

### На VPS (`/etc/masterdoc-zitadel/.env`, `chmod 600`)

Скопируй с `deploy/.env.example`, заполни:

| Переменная | Примечание |
|------------|------------|
| `ZITADEL_DOMAIN` | тот же FQDN |
| `ZITADEL_MASTERKEY` | ровно 32 символа, generate once, backup offline |
| `POSTGRES_ADMIN_PASSWORD` | сильный пароль |
| `ZITADEL_DATABASE_POSTGRES_DSN` | с тем же паролем |
| `LETSENCRYPT_EMAIL` | если Let's Encrypt overlay |

Генерация masterkey:

```bash
tr -dc A-Za-z0-9 </dev/urandom | head -c 32
```

## 1. DNS и TLS

1. A-запись `${ZITADEL_DOMAIN}` → `${ZITADEL_DEPLOY_HOST}`.
2. Вариант A: TLS на Traefik (Let's Encrypt overlay — см. upstream docs).
3. Вариант B (рекомендуем, если уже есть nginx): TLS на nginx → HTTP к Traefik на localhost; compose overlay `docker-compose.mode-external-tls.yml`. Пример: [`deploy/nginx.example.conf`](../deploy/nginx.example.conf).

`ZITADEL_DOMAIN` / external port / `EXTERNALSECURE` должны совпадать с публичным URL, иначе «Instance not found».

## 2. Деплой Compose на VPS

С ноутбука (после `source` env):

```bash
ssh -i "$ZITADEL_SSH_KEY_PATH" "${ZITADEL_DEPLOY_USER}@${ZITADEL_DEPLOY_HOST}"
```

На сервере:

```bash
sudo mkdir -p /opt/masterdoc-zitadel /etc/masterdoc-zitadel
# скопируй содержимое deploy/ в /opt/masterdoc-zitadel (rsync/scp из клона репо)
# .env только в /etc/masterdoc-zitadel/.env — не в git

cd /opt/masterdoc-zitadel
sudo ln -sf /etc/masterdoc-zitadel/.env .env

# MVP за reverse-proxy (external TLS):
sudo docker compose --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.mode-external-tls.yml \
  up -d --wait
```

Первый admin: см. логи/документацию Zitadel first instance (смена дефолтного пароля обязательна).

## 3. Machine user + PAT (для Terraform)

В Console:

1. Users → Service User → `terraform-masterdoc`.
2. Managers → Org Owner (на bootstrap; потом сузить).
3. Personal Access Token → сохранить **только** в `ZITADEL_TOKEN` (локальный env / GitHub secret).
4. Записать `ZITADEL_ORG_ID` org владельца продукта.

В чат с агентом **не** присылай PAT. Достаточно: «domain / org id готовы, PAT в env».

## 4. Terraform platform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # gitignored значения
# или экспортируй ZITADEL_DOMAIN / ZITADEL_TOKEN / ZITADEL_ORG_ID

terraform init
terraform plan
terraform apply
```

Создаёт: project `masterdoc-toir`, 5 roles, OIDC native + web, login policy (no self-signup).

## 5. Verify

```bash
cd verify
./gradlew test          # всегда (WireMock) — также в CI
# live (opt-in), когда env с TOKEN:
./gradlew liveTest
```

## 6. Invite smoke (вручную)

1. Создай demo Organization клиента (или используй org владельца для теста).
2. Invite user с ролью `engineer`.
3. First password → OIDC debugger / app → JWT содержит `sub`, org, roles.

## 7. Бэкапы

- Регулярный dump Postgres volume `postgres-data`.
- Храни offline копию `ZITADEL_MASTERKEY` — без неё encrypted-at-rest данные недоступны.
