# AGENTS.md — Infrastructure Repository

This repository is a **Docker Compose infrastructure stack** managed with
[go-task](https://taskfile.dev). There is no application code, no test suite,
and no linter. The guidance below covers validation, deployment, and
conventions an agent should follow when editing files here.

---

## Repository Layout

```
.
├── docker-compose.yaml               # Single compose file — all services
├── Taskfile.yaml                     # Task runner (go-task)
├── .env.remote                       # Remote deployment environment variables
├── config/
│   ├── clickhouse/                   # ClickHouse server config (XML)
│   │   ├── config.xml
│   │   ├── users.xml
│   │   ├── cluster.xml
│   │   └── custom-function.xml
│   ├── otel-collector/
│   │   └── otel-collector-config.yaml  # SigNoz OTel Collector pipeline
│   ├── signoz/
│   │   └── otel-collector-opamp-config.yaml
│   └── traefik/
│       └── traefik.yaml
├── docker/
│   └── ollama/
│       └── Dockerfile                # Custom Ollama image (gemma3 pre-pulled)
└── data/                             # Runtime data — gitignored, never edit
```

---

## Commands

### Validate compose file (no Docker daemon required)

```bash
docker compose config --quiet
```

Run this after every change to `docker-compose.yaml` to catch YAML and
schema errors before committing.

### Start the stack locally

```bash
docker compose up -d
```

### Stop and remove containers

```bash
docker compose down
```

### Rebuild a single service (e.g. after editing the Ollama Dockerfile)

```bash
docker compose build ollama
docker compose up -d ollama
```

### Tail logs for a specific service

```bash
docker compose logs -f <service-name>
```

### Remote deployment (requires SSH host alias `docker` and go-task installed)

```bash
# Sync config files to remote server, then deploy
task remote:deploy

# Sync config files only
task remote:sync

# Run an arbitrary compose command on remote
task remote -- ps

# Remove all remote containers and volumes
task remote:clean
```

Remote environment variables are loaded from `.env.remote`:
- `DOCKER_CONTEXT=remote` — uses the `remote` Docker context (SSH)
- `DATA_DIR=/srv/docker-data` — persistent data root on the remote host
- `CONFIG_DIR=/srv/appdata` — config files root on the remote host

There are **no test commands** — this is a pure infrastructure repository.

---

## Service Overview

| Service | Image | Host Port(s) |
|---|---|---|
| `signoz` | `signoz/signoz:v0.114.1` | **3301** (UI) |
| `otel-collector` | `signoz/signoz-otel-collector:v0.144.2` | 4317 (gRPC), 4318 (HTTP), 13133, 1888, 8888 |
| `clickhouse` | `clickhouse/clickhouse-server:25.5.6` | — (internal only) |
| `zookeeper-1` | `signoz/zookeeper:3.7.1` | — (internal only) |
| `traefik` | `traefik:v3.6.4` | 80, 443, 9000 (dashboard) |
| `temporal` | `temporalio/auto-setup:1.29.1` | 7233 |
| `temporal-ui` | `temporalio/ui:2.34.0` | **8080** |
| `postgresql` | `postgres:16` | 5432 |
| `mongodb` | `mongo:7.0` | 27017 |
| `redis` | `redis:7.2-alpine` | 6379 |
| `elasticsearch` | `elasticsearch:7.17.27` | 9200 |
| `ollama` | custom (ollama/ollama:0.15.1 + gemma3) | 11434 |
| `n8n` | `n8nio/n8n:2.9.4` | 5678 |

All services share the `infrastructure` bridge network. Internal service
communication uses container names as hostnames (e.g. `clickhouse:9000`).

---

## docker-compose.yaml Conventions

- **YAML anchors** are used for shared config blocks. Always extend them
  rather than duplicating fields:
  - `*common` — `restart: unless-stopped` + log rotation
  - `*clickhouse-defaults` — ClickHouse image, healthcheck, ulimits,
    `depends_on` for init-clickhouse + zookeeper-1
  - `*db-depend` — `depends_on: clickhouse: condition: service_healthy`
- **Pin all image tags** — never use `latest` except for services that
  already use it (currently none after the SigNoz migration). Use a
  specific version tag for every image.
- **Port mapping format** — always `"HOST:CONTAINER"` as a quoted string.
- **Volume paths** — use the `${CONFIG_DIR:-./config}` and
  `${DATA_DIR:-./data}` variables so the same file works locally and
  remotely. Stateful data goes in named volumes (SigNoz/ClickHouse) or
  bind mounts under `./data/` (databases). Config files are always
  bind-mounted read-only from `./config/`.
- **No `version:` key** — the top-level `version` field is obsolete in
  modern Compose; do not add it.
- **`name: infrastructure`** — the project name is explicitly set; do not
  change it as it affects network and volume naming.
- **Healthchecks** — add a `healthcheck` to any service that other
  services depend on via `condition: service_healthy`.
- **Section comments** — keep the `# ---` section dividers that separate
  the observability stack from general infrastructure services.

---

## OTel Collector Config Conventions (`config/otel-collector/`)

- The collector uses the **SigNoz-specific image** which includes custom
  exporters (`clickhousetraces`, `signozclickhousemetrics`,
  `clickhouselogsexporter`, `signozclickhousemeter`, `metadataexporter`)
  and the `signozmeter` connector. These are not available in the standard
  `otel/opentelemetry-collector-contrib` image.
- All three signal types (traces, logs, metrics) must be exported to
  ClickHouse. Do not remove any pipeline.
- The `signozspanmetrics/delta` processor on the traces pipeline generates
  APM RED metrics — keep it.
- ClickHouse DSN format: `tcp://clickhouse:9000/<database>`.

---

## ClickHouse Config Conventions (`config/clickhouse/`)

- Config is split across four XML files following the upstream SigNoz
  layout. Do not merge them into one file.
- `cluster.xml` defines the ZooKeeper connection and the `cluster` remote
  server used by the replicated table engine. The cluster name `cluster`
  must match the `SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_CLUSTER` env var.
- `custom-function.xml` registers the `histogramQuantile` UDF. The binary
  is downloaded at startup by `init-clickhouse` into the shared
  `clickhouse-user-scripts` named volume.

---

## Traefik Config Conventions (`config/traefik/`)

- Services are **not** exposed by default (`exposedByDefault: false`). To
  route a container through Traefik, add
  `traefik.enable=true` and appropriate router/service labels to the
  compose service.
- Traefik ships its own logs, metrics, and traces to the `otel-collector`
  via OTLP HTTP on port 4318. Keep these endpoints consistent with the
  collector's HTTP receiver address.
- The log endpoint currently uses `https://` — this is a known
  misconfiguration (the collector does not terminate TLS). Change to
  `http://` if enabling Traefik log forwarding.

---

## Dockerfile Conventions (`docker/`)

- The only custom image is `docker/ollama/Dockerfile`. It pre-bakes the
  `gemma3` model into the image at build time using a background `ollama
  serve` during the `RUN` layer.
- Update the base image tag (`ollama/ollama:x.y.z`) when upgrading Ollama.
- Do not add a `.dockerignore` unless the build context becomes large — the
  context is currently the repo root and the Dockerfile is small.

---

## General Conventions

- **No secrets in files.** The only credentials in this repo
  (`SIGNOZ_TOKENIZER_JWT_SECRET=secret`, Temporal DB passwords) are
  development defaults. Production secrets must be injected via `.env`
  files that are not committed.
- **`.gitignore`** excludes `/.idea` and `/data`. Do not commit IDE files
  or runtime data.
- **File format** — all config files use 2-space indentation. YAML files
  must be valid YAML (run `docker compose config --quiet` for compose
  files). XML files must be well-formed.
- **No shell scripts** — automation lives in `Taskfile.yaml` inline
  commands. Keep it that way; avoid adding separate `.sh` files unless
  the logic is too complex for an inline command.
- **Changing a service name** affects the Docker DNS hostname used by
  other services. Update all references (other services' env vars,
  config files, `depends_on` keys) atomically.
