# Deploy — Zitadel + Postgres (RU VPS)

Official-style Compose pack (Zitadel v4 + Traefik + Postgres).

## Files

| File | Role |
|------|------|
| `docker-compose.yml` | base stack |
| `docker-compose.mode-external-tls.yml` | behind nginx/LB that terminates TLS |
| `.env.example` | copy to `/etc/masterdoc-zitadel/.env` on server |
| `nginx.example.conf` | sample TLS terminator |

## Typical prod command (TLS on nginx)

```bash
docker compose --env-file /etc/masterdoc-zitadel/.env \
  -f docker-compose.yml \
  -f docker-compose.mode-external-tls.yml \
  up -d --wait
```

Full steps: [../docs/RUNBOOK.md](../docs/RUNBOOK.md).

Upstream reference: https://zitadel.com/docs/self-hosting/deploy/compose
