# LXC Migration Plan

## Architecture After Migration

```
Proxmox Host (192.168.1.231)
├── CT 101: Pi-hole (192.168.1.33)         [existing, unchanged]
├── CT 100: Plex                            [existing, unchanged]
├── CT 110-112: Transmission/Radarr/Sonarr  [existing, unchanged]
├── CT 113: forgejo (192.168.1.40)          [NEW LXC]
│   └── Docker: forgejo
├── CT 114: data-services (192.168.1.41)     [NEW LXC]
│   └── Docker: postgresql, elasticsearch, redis
└── VM 102: debian-docker (16GB RAM)         [MODIFIED - reduced from 32GB]
    └── Docker: signoz stack, traefik, temporal, temporal-ui
```

## Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | RAM allocation | Reduce Docker VM 32GB → 16GB |
| 2 | PG + ES + Redis | Combined in one "data-services" LXC |
| 3 | Forgejo | Own LXC (fresh install, no data migration) |
| 4 | Data persistence | Host bind-mounts (`/srv/lxc-data/`) |
| 5 | Config persistence | Host bind-mounts (`/srv/lxc-config/`) |
| 6 | Runtime inside LXCs | Docker with `nesting=1` |
| 7 | IPs | Static — forgejo `.40`, data-services `.41` |
| 8 | DNS | Pi-hole at `192.168.1.33` |
| 9 | OS template | Debian 12 |
| 10 | Disk sizes | forgejo 8G, data-services 20G |
| 11 | CT IDs | forgejo=113, data-services=114 |
| 12 | Temporal | Stays in QEMU compose, connects to PG/ES over network |
| 13 | Redis | Moves to data-services LXC, apps update connection strings later |
| 14 | MongoDB | Removed entirely (leftover, unused) |
| 15 | Repo layout | `qemu/`, `forgejo/`, `data-services/` at root level |
| 16 | `.env.remote` | One per subdirectory |

## Repository Structure

```
infrastructure/
├── AGENTS.md
├── .gitignore
├── Taskfile.yaml                    ← updated tasks
├── qemu/                            ← VM 102
│   ├── .env.remote
│   ├── docker-compose.yaml          ← signoz stack + traefik + temporal (updated connections)
│   └── config/
│       ├── clickhouse/
│       ├── otel-collector/
│       ├── signoz/
│       └── traefik/
├── forgejo/                         ← CT 113
│   ├── .env.remote
│   ├── docker-compose.yaml
│   └── config/
├── data-services/                   ← CT 114
│   ├── .env.remote
│   ├── docker-compose.yaml
│   └── config/
│       └── postgresql/
│           └── init/
└── data/                            ← gitignored, local dev only
```

## Services Removed from QEMU Compose

- `forgejo` → `forgejo/` directory, CT 113
- `postgresql` → `data-services/` directory, CT 114
- `elasticsearch` → `data-services/` directory, CT 114
- `redis` → `data-services/` directory, CT 114
- `mongodb` → removed entirely

## Services Staying in QEMU Compose

- `init-clickhouse`, `zookeeper-1`, `clickhouse`, `signoz`, `signoz-telemetrystore-migrator`, `otel-collector`
- `traefik`
- `temporal`, `temporal-ui` (updated: `POSTGRES_SEEDS=192.168.1.41`, `ES_SEEDS=192.168.1.41`)

## Execution Steps

### Phase 1: Proxmox Setup

1. Reduce Docker VM RAM: `qm set 102 --memory 16384`, reboot VM
2. Create host directories on Proxmox:
   - `/srv/lxc-data/{forgejo,postgresql,elasticsearch,redis}`
   - `/srv/lxc-config/{forgejo,data-services}`
3. Create CT 113 (forgejo): Debian 12, 2 cores, 1GB RAM, 8G disk, IP `192.168.1.40/24`, gw `192.168.1.1`, DNS `192.168.1.33`, `nesting=1`, mount points for data/config
4. Create CT 114 (data-services): Debian 12, 2 cores, 3GB RAM, 20G disk, IP `192.168.1.41/24`, gw `192.168.1.1`, DNS `192.168.1.33`, `nesting=1`, mount points for data/config
5. Install Docker in both LXCs
6. Start both LXCs

### Phase 2: Repo Restructure

7. Move current `docker-compose.yaml` and `config/` to `qemu/`
8. Create `forgejo/docker-compose.yaml` and `forgejo/.env.remote`
9. Create `data-services/docker-compose.yaml` and `data-services/.env.remote`
10. Move `config/postgresql/` to `data-services/config/postgresql/`
11. Remove migrated services (forgejo, postgresql, elasticsearch, redis) from `qemu/docker-compose.yaml`
12. Update Temporal connection strings in QEMU compose to use `192.168.1.41`
13. Update `Taskfile.yaml` for new directory layout
14. Update `AGENTS.md` for new architecture

### Phase 3: Deploy

15. Deploy data-services on CT 114
16. Deploy forgejo on CT 113
17. Redeploy QEMU stack with updated compose
18. Verify all services are healthy and communicating

### Phase 4: Cleanup

19. Remove MongoDB data from Docker VM
20. Update any app connection strings pointing at old service names