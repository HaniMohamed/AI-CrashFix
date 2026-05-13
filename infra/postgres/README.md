# Self-hosted Postgres for AI Crash Fix crash store

Team-shared crash pipeline state uses Postgres when the backend sets
`AI_CRASH_FIX_CRASH_STORE_BACKEND=postgres` and `AI_CRASH_FIX_CRASH_DB_URL`.
The repo registry stays on local SQLite on each machine.

## Start

```bash
cd infra/postgres
cp .env.example .env
# edit .env and set POSTGRES_PASSWORD
docker compose up -d
docker compose ps
```

Connection URL for the app (replace host and password):

```text
postgresql://ai_crash_fix:YOUR_PASSWORD@HOST:5432/ai_crash_fix
```

## Network

Bind Postgres only on interfaces your team can reach (office LAN or Tailscale).
Do not expose port 5432 on a public home router without a VPN.

## Backups

Schedule `pg_dump` to durable storage, for example:

```bash
docker compose exec -T postgres pg_dump -U ai_crash_fix ai_crash_fix > backup.sql
```

Restore into a fresh volume only after testing on a throwaway instance.
