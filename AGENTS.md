# Infrastructure

Docker-based infrastructure repository deploying across Proxmox LXCs.

## Commands

```bash
# Deploy edge proxy (Traefik) to CT 115
docker --context edge-proxy compose --env-file edge-proxy/.env.remote -f edge-proxy/docker-compose.yaml up -d --build

# Deploy Forgejo to CT 113
docker --context forgejo compose --env-file forgejo/.env.remote -f forgejo/docker-compose.yaml up -d --build

# Deploy Temporal to CT 116
docker --context temporal compose --env-file temporal/.env.remote -f temporal/docker-compose.yaml up -d --build

# Deploy SigNoz to CT 117
docker --context signoz compose --env-file signoz/.env.remote -f signoz/docker-compose.yaml up -d --build

# General compose operations (replace <stack> with edge-proxy/forgejo/temporal/signoz)
docker --context <context> compose --env-file <stack>/.env.remote -f <stack>/docker-compose.yaml ps
docker --context <context> compose --env-file <stack>/.env.remote -f <stack>/docker-compose.yaml logs -f

# Clean up a stack
docker --context <context> compose --env-file <stack>/.env.remote -f <stack>/docker-compose.yaml rm -v -f
```

## Architecture

| Host | Type | IP | Services |
|------|------|----|----------|
| CT 113 | LXC | 192.168.1.40 | Forgejo, Forgejo Runner, Docker-in-Docker, PostgreSQL (forgejo DB) |
| CT 115 | LXC | 192.168.1.42 | Traefik (edge proxy) |
| CT 116 | LXC | 192.168.1.43 | Temporal, Temporal-UI, PostgreSQL (temporal DB) |
| CT 117 | LXC | 192.168.1.44 | SigNoz, OTEL Collector, ClickHouse (telemetry storage) |

> Note: Each stack is self-contained — its database/store runs in the same LXC and is reached over the stack's internal Docker network by service name (e.g. `postgresql`, `clickhouse`).

### External Access (via CT 115 edge proxy)

| Domain | Backend | Service |
|--------|---------|---------|
| git.de-meyer.nl | 192.168.1.40:3000 | Forgejo web |
| git.de-meyer.nl:222 | 192.168.1.40:222 | Forgejo SSH |
| signoz.de-meyer.nl | 192.168.1.44:8080 | SigNoz web |

### Direct Access (non-HTTP)

| Service | Host | Port | Notes |
|---------|------|------|-------|
| OTEL ingestion (gRPC) | CT 117 | 4317 | Applications send telemetry here |
| OTEL ingestion (HTTP) | CT 117 | 4318 | Applications send telemetry here |
| Temporal gRPC | CT 116 | 7233 | Applications connect here |
| ClickHouse native | CT 117 | 9000 | SigNoz telemetry storage (in-stack) |
| ClickHouse HTTP | CT 117 | 8123 | SigNoz telemetry storage (in-stack) |
| PostgreSQL (temporal) | CT 116 | 5432 | Temporal DB (in-stack) |
| PostgreSQL (forgejo) | CT 113 | 5432 | Forgejo DB (in-stack) |

### Data & Config Paths

| Host | Data | Config |
|------|------|--------|
| CT 113 | `/srv/lxc-data` (mp0, host: `/srv/lxc-data/forgejo`) | `/srv/lxc-config` (mp1, host: `/srv/lxc-config/forgejo`) |
| CT 115 | — | `/srv/lxc-config` (mp0, host: `/srv/lxc-config/edge-proxy`) |
| CT 116 | `/srv/lxc-data` (mp0, host: `/srv/lxc-data/temporal`) | `/srv/lxc-config` (mp1, host: `/srv/lxc-config/temporal`) |
| CT 117 | `/srv/lxc-data` (mp0, host: `/srv/lxc-data/signoz`) | `/srv/lxc-config` (mp1, host: `/srv/lxc-config/signoz`) |

### Subdirectories

| Directory | Purpose | Target |
|-----------|---------|--------|
| `edge-proxy/` | Traefik reverse proxy (TLS termination) | CT 115 |
| `forgejo/` | Forgejo git server + PostgreSQL (forgejo DB) + Runner + DinD | CT 113 |
| `temporal/` | Temporal workflow engine + UI + PostgreSQL (temporal DB) | CT 116 |
| `signoz/` | SigNoz observability + OTEL Collector + ClickHouse (telemetry storage) | CT 117 |

### Key Services

| Service | Host | Ports | Notes |
|---------|------|-------|-------|
| Traefik | CT 115 | 80, 443, 222, 9000 | Edge proxy, TLS termination via Let's Encrypt |
| PostgreSQL (temporal) | CT 116 | 5432 | Temporal DB (in-stack, reached as `postgresql` by Temporal) |
| Temporal | CT 116 | 7233 | Workflow engine, connects to in-stack PostgreSQL |
| Temporal-UI | CT 116 | 8080 | Temporal web interface |
| ClickHouse | CT 117 | 9000, 8123 | SigNoz telemetry storage (single-node, no replication, in-stack) |
| ZooKeeper | CT 117 | 2181 | ClickHouse coordination (optional, use `--profile with-zookeeper`) |
| SigNoz | CT 117 | 8080 | Observability UI (via Traefik), connects to in-stack ClickHouse |
| OTEL Collector | CT 117 | 4317, 4318 | Telemetry ingestion, connects to in-stack ClickHouse |
| PostgreSQL (forgejo) | CT 113 | 5432 | Forgejo DB (in-stack, reached as `postgresql` by Forgejo) |
| Forgejo | CT 113 | 3000, 222 | Git server, connects to in-stack PostgreSQL |
| Forgejo Runner | CT 113 | — | Actions runner (DinD mode), connects to Forgejo via internal network |
| Docker-in-Docker | CT 113 | — | Privileged DinD sidecar for Forgejo Runner job containers |

### Forgejo Action Runner

The Forgejo Runner executes Actions workflows using Docker-in-Docker (DinD) for isolation. The runner and DinD sidecar are part of the `forgejo` docker-compose stack.

**Config:** `forgejo/config/runner/runner-config.yml` (mounted into the runner container)

**Data paths on CT 113:**
- Runner data: `/srv/lxc-data/runner` (cache, registration state)
- DinD storage: `/srv/lxc-data/dind` (Docker image cache for job containers)
- Runner config: `/srv/lxc-config/runner/runner-config.yml`

**Runner registration (first-time setup):**

1. Create directories on CT 113 and set permissions:
   ```bash
   mkdir -p /srv/lxc-data/runner/.cache /srv/lxc-data/dind /srv/lxc-config/runner
   chown -R 1001:1001 /srv/lxc-data/runner
   chmod 775 /srv/lxc-data/runner/.cache
   chmod g+s /srv/lxc-data/runner/.cache
   ```
2. Copy `forgejo/config/runner/runner-config.yml` to CT 113 at `/srv/lxc-config/runner/runner-config.yml`
3. Register the runner in the Forgejo UI:
   - Go to `https://git.de-meyer.nl/admin/actions/runners`
   - Click "Create new runner", name it (e.g. `infra-runner`)
   - Copy the **UUID** and **Token**
4. Edit `/srv/lxc-config/runner/runner-config.yml` on CT 113:
   - Replace `REPLACE_WITH_UUID` with the UUID from the UI
   - Replace `REPLACE_WITH_TOKEN` with the Token from the UI
5. Deploy the stack:
   ```bash
   docker --context forgejo compose --env-file forgejo/.env.remote -f forgejo/docker-compose.yaml up -d
   ```
6. Verify the runner shows as online at `https://git.de-meyer.nl/admin/actions/runners`

**Labels configured:**
- `ubuntu-latest` — `docker://node:lts` (GitHub Actions compatible)
- `docker` — `docker://ghcr.io/catthehacker/ubuntu:act-22.04` (broader compatibility)

**Notes:**
- The runner connects to Forgejo at `http://forgejo:3000` (internal Docker network)
- The DinD container runs privileged (required for nested Docker); job containers are isolated from the host Docker daemon
- The runner runs as user `1001:1001` (non-root)
- To regenerate the default config: `docker exec forgejo-runner forgejo-runner generate-config`

## Network Notes

- Traefik on CT 115 routes external traffic to backends on other hosts via file provider (dynamic YAML configs)
- Each stack is self-contained: services reach their co-located DB/store over the stack's internal Docker network by service name (`postgresql`, `clickhouse`)
- Temporal on CT 116 connects to its in-stack PostgreSQL (`postgresql:5432`); Elasticsearch is no longer used (`ENABLE_ES=false`)
- SigNoz on CT 117 connects to its in-stack ClickHouse (`clickhouse:9000`)
- Each LXC has its own Docker bridge network (`forgejo`, `edge-proxy`, `temporal`, `signoz`)
- ClickHouse is single-node (no replication); `cluster.xml` defines a single-replica cluster for compatibility

## Remote Deployment Prerequisites

1. CT 113: `forgejo` Docker network: `docker network create forgejo`
2. CT 115: `edge-proxy` Docker network: `docker network create edge-proxy`
3. CT 116: `temporal` Docker network: `docker network create temporal`
4. CT 117: `signoz` Docker network: `docker network create signoz`
5. Bind-mount directories must exist on each host

## Notes

- SigNoz includes OTEL collector config in `signoz/config/otel-collector/` and `signoz/config/signoz/`; ClickHouse is in-stack (service `clickhouse`, DSN `tcp://clickhouse:9000`)
- Forgejo Runner config in `forgejo/config/runner/runner-config.yml` — requires UUID/token from Forgejo UI
- Traefik dynamic routing configs in `edge-proxy/config/traefik/dynamic/` — add new services as YAML files
- Docker contexts: `edge-proxy` (CT 115), `forgejo` (CT 113), `temporal` (CT 116), `signoz` (CT 117)
- **LXC containers are privileged** (required for Docker-in-LXC sysctl support)
- **Proxmox sysctl**: `net.ipv4.ip_unprivileged_port_start=0` set in `/etc/sysctl.d/99-docker-lxc.conf`
- **LXC configs** include: `unprivileged: 0`, `lxc.apparmor.profile: unconfined`, `lxc.cgroup2.devices.allow: a`, `lxc.cap.drop: `
