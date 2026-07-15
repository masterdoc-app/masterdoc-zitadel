# Служба авторизации Masterdoc TOiR (канон)

Источник правды для IdP. Краткий обзор в продуктовых docs: [TOIR_AI_SYSTEM_DESIGN.md §8.1](https://github.com/AntonButov/masterdoc/blob/main/TOIR_AI_SYSTEM_DESIGN.md) (после pointer-правки).

## Решение

| Тема | Выбор |
|------|--------|
| Продукт IdP | **Zitadel** (OIDC), B2B Organizations |
| Hosting | **Self-host на инфраструктуре в РФ** (Docker Compose) — не Zitadel Cloud |
| Почему не Cloud | Регионы Cloud: US / EU / CH / AU; **России нет** — не подходит для ПДн (152-ФЗ) |
| Лицензия OSS | AGPL; при необходимости commercial license позже |
| Пароли | Только в Zitadel; свой backend **не** хранит пароли и **не** делает `POST /auth/login` |

## Multi-tenant

| Zitadel | Masterdoc TOiR |
|---------|----------------|
| **1 Instance** (self-host) | весь SaaS-продукт |
| **Organization** | один клиент (компания) |
| **User** в org | сотрудник клиента |
| **Project role** | `admin` \| `dispatcher` \| `engineer` \| `requester` \| `reporter` |
| **OIDC Application(s)** | клиенты KMP/Web — **общие на продукт**, не по app на org |

Клиент **не** передаёт свой instance. Логин идёт на ваш домен IdP; tenant = org claim в JWT.

Создание клиентских Organization — операционный процесс (Console / позже API). Terraform в этом репо поднимает **только platform** (project, roles, OIDC apps, login policy).

## Методы входа (MVP)

| Метод | Статус |
|-------|--------|
| Email + пароль | единственный |
| Invite-only регистрация | да |
| Self-signup | **выключен** |
| Magic link / MFA / Social / SAML | backlog |

## Поток

1. Admin создаёт Organization клиента в Zitadel.
2. Invite user (email + роль) → пользователь задаёт пароль.
3. KMP: OIDC Authorization Code + **PKCE** → `access_token` + `refresh_token`.
4. API (будущий gateway): Bearer JWT → verify issuer / audience / JWKS → `sub`, org, `roles`.
5. Доступ к Site — **не** в Zitadel (`user_site_access` в future `access-service`).

## Claims (минимум)

| Claim | Назначение |
|-------|------------|
| `sub` | стабильный user id во всём backend |
| org (Zitadel org id / mapping) | текущий клиент — в docs product как `org_id` |
| `roles` / project roles assertion | одна из пяти ролей |
| `email` | опционально для `GET /me` |

В Terraform для OIDC apps включены `access_token_role_assertion` и `id_token_role_assertion`.

## Что IdP не делает

- не хранит `user_site_access`, `org_settings`, feature flags продукта;
- не выдаёт собственные session id вместо OIDC;
- не заменяет Spring Boot gateway.

## Секреты и хост

IP VPS, SSH, domain, PAT, DB passwords, `ZITADEL_MASTERKEY` — **только GitHub Secrets**. CI материализует `.env` на VPS при деплое (сервер может смениться).

**Деплой Compose — только из CI.** См. [SECRETS.md](SECRETS.md), [RUNBOOK.md](RUNBOOK.md).

## Артефакты в репо

| Путь | Назначение |
|------|------------|
| [`deploy/`](../deploy/) | Docker Compose (официальный pack Zitadel) + nginx example |
| [`terraform/`](../terraform/) | platform: project, 5 roles, native+web OIDC, login policy |
| [`verify/`](../verify/) | контрактные инварианты (TDD unit + optional live) |
| CI | на каждый push/PR: `terraform validate` + unit tests |

## Операции

Деплой, PAT, `terraform apply`, invite smoke — [RUNBOOK.md](RUNBOOK.md).
