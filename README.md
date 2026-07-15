# masterdoc-zitadel

Self-host **Zitadel** для Masterdoc TOiR на инфраструктуре в **РФ** (152-ФЗ).  
Не используем Zitadel Cloud.

| | |
|--|--|
| Канон auth | [docs/AUTHORIZATION.md](docs/AUTHORIZATION.md) |
| Эксплуатация | [docs/RUNBOOK.md](docs/RUNBOOK.md) |
| Deploy | [deploy/](deploy/) |
| Platform IaC | [terraform/](terraform/) |
| Invariants | [verify/](verify/) |

## CI

Каждый push/PR:

1. `terraform fmt -check` + `terraform validate`
2. `./gradlew test` в `verify/` (unit, без живого IdP)

## Secrets

Не коммить IP, PAT, SSH keys, DB passwords, masterkey.  
Имена и куда класть — [docs/RUNBOOK.md](docs/RUNBOOK.md) §0.
