# Deploy — Zitadel + Postgres (RU VPS)

Official-style Compose pack (Zitadel v4 + Traefik + Postgres).

## Files

| File | Role |
|------|------|
| `docker-compose.yml` | base stack |
| `docker-compose.mode-external-tls.yml` | behind nginx/LB that terminates TLS |
| `.env.example` | copy to `/etc/masterdoc-zitadel/.env` on server |
| `nginx.example.conf` | sample TLS terminator |

## Typical prod (TLS on nginx)

Traefik binds `127.0.0.1:8080`; nginx terminates TLS and proxies there (`nginx.example.conf`).

Deploy: GitHub Actions only — see [../docs/RUNBOOK.md](../docs/RUNBOOK.md).

Upstream: https://zitadel.com/docs/self-hosting/deploy/compose
