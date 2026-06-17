# Infrastructure

Docker-based infrastructure repository deploying to a remote server.

## Commands

```bash
# Deploy shared infra or it-tools to remote (use docker context directly, task is broken)
docker --context remote compose --env-file .env.remote --profile remote up -d --build

# Run arbitrary docker compose on remote
docker --context remote compose --env-file .env.remote --profile remote up -d
docker --context remote compose --env-file .env.remote --profile remote ps
docker --context remote compose --env-file .env.remote --profile remote logs -f

# Deploy just it-tools
docker --context remote compose --env-file .env.remote --profile remote -f it-tools/docker-compose.yaml up -d --build

# Clean up remote stack
docker --context remote compose --env-file .env.remote --profile remote rm -v -f
```

## Architecture

- **Remote target**: `docker` context (host alias), uses `.env.remote` env vars
- **DATA_DIR**: `/srv/docker-data` — databases, volumes
- **CONFIG_DIR**: `/srv/appdata` — bind-mounted configs

### Subdirectories

| Directory | Purpose |
|-----------|---------|
| `shared/` | Core infra: SigNoz, Traefik, Temporal, PostgreSQL, MongoDB, Elasticsearch, Redis, (Ollama) |
| `it-tools/` | Lightweight tools (corentinth/it-tools) |

### Key Services

| Service | Ports | Notes |
|---------|------|-------|
| Traefik | 80, 443, 9000 | Reverse proxy, requires Docker socket mount |
| SigNoz | 3301 | Observability (traces, logs, metrics) |
| ClickHouse | 8123 | SigNoz backend |
| Temporal | 7233, 7234 | Workflow engine |
| PostgreSQL | 5432 | Temporal backend |
| MongoDB | 27017 | |
| Elasticsearch | 9200 | |
| Redis | 6379 | |

## Remote Deployment Prerequisites

1. Remote Docker host must have `infrastructure` network: `docker network create infrastructure`
2. `DATA_DIR` and `CONFIG_DIR` volumes must exist on remote (bind-mounted from host)

## Notes

- `shared/docker-compose.yaml` uses `!!merge` YAML anchors — edits require proper YAML merge syntax
- `ollama` service has `profiles: [remote]` — only deploys with `--profile remote`
- SigNoz includes OTEL collector config in `./shared/config/otel-collector/` and `./shared/config/signoz/`
- **Traefik TLS routers**: Must specify `tls.certResolver=letsencrypt` or Traefik uses self-signed certs → `MOZILLA_PKIX_ERROR_SELF_SIGNED_CERT` errors
