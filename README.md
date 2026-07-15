# masterdoc-zitadel

Self-host **Zitadel** для Masterdoc TOiR на инфраструктуре в **РФ** (152-ФЗ).  
Не используем Zitadel Cloud.

| | |
|--|--|
| Канон auth | [docs/AUTHORIZATION.md](docs/AUTHORIZATION.md) |
| Эксплуатация | [docs/RUNBOOK.md](docs/RUNBOOK.md) |
| Secrets | [docs/SECRETS.md](docs/SECRETS.md) |
| Deploy | [deploy/](deploy/) — **только CI** |
| Platform IaC | [terraform/](terraform/) |
| Invariants | [verify/](verify/) |

## CI

Каждый push/PR:

1. `terraform fmt -check` + `terraform validate`
2. `./gradlew test` в `verify/` (unit, без живого IdP)

**Деплой:** workflow [Deploy](.github/workflows/deploy.yml) — только GitHub Actions (`master` / `workflow_dispatch`). С ноутбука не деплоим.

## Secrets

IP, SSH, PAT, DB passwords, masterkey — не в git.  
Класть в GitHub Actions secrets (+ `/etc/…/.env` на VPS для Compose).  
Локальный env для деплоя не нужен — [docs/SECRETS.md](docs/SECRETS.md).
