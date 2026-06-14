# AGENTS.md — depot

This file is the canonical reference for any AI agent or developer working with the local development control plane. Read it before making changes.

---

## What This Is

**depot** is the local development control plane for the Dola FX monorepo — analogous to `quartermaster` (which provisions cloud infrastructure) but targeting developer machines.

It owns the shared local infrastructure that every `fx-*` service depends on:
- `secure_idmsa_network` — the Docker bridge network all services communicate over
- `depot-cassandra` — one shared Cassandra instance replacing the five per-service instances
- `depot-redpanda` — one shared Redpanda (Kafka-compatible) broker

It also provides the startup orchestration layer: dependency ordering, health-gated startup, and a live status UI via Tilt.

---

## Structure

```
depot/
├── Tiltfile                  — Tilt control plane: docker_compose() calls + dc_resource(resource_deps=[])
├── justfile                  — Orchestration: just up/down call tilt; up-*/down-* targets use docker compose
├── infra/
│   └── docker-compose.yml    — Shared network, depot-cassandra, depot-redpanda
└── AGENTS.md                 — This file
```

---

## Prerequisites

```bash
brew install tilt   # https://docs.tilt.dev/install.html
```

Fill in the SMTP credential in `../odin/.env.local` before first run:
```
SMTP_CONNECTION_URI="smtps://you@gmail.com:YOUR_APP_PASSWORD@smtp.gmail.com:465/?skip_ssl_verify=true"
```

---

## Usage

### With Tilt (recommended)

```bash
cd depot
tilt up            # start everything; opens UI at http://localhost:10350
tilt down          # stop everything
```

Tilt shows all service health, logs, and dependency state in a browser UI. It enforces the startup ordering defined in `Tiltfile` via `dc_resource(resource_deps=[...])` — services will not start until their declared dependencies are healthy.

### Individual service restarts (docker compose, no Tilt needed)

```bash
cd depot
just up-wms        # restart a single service
just down-oms      # stop a single service
just status        # show running containers across all stacks
just health        # hit /actuator/health on each service
just urls          # print all service URLs
just logs <stack>  # tail logs for a stack (infra|iam|sync|fx-backend|fx-ledger|wms|oms|treasury)
just nuke          # stop everything + delete all volumes (full reset)
```

---

## Shared Infrastructure

### Cassandra (`depot-cassandra`)

| Property | Value |
|---|---|
| Container name | `depot-cassandra` |
| Image | `cassandra:4.1` |
| Host port | `9042` |
| Cluster | `dola_cluster` / `datacenter1` |

Each service creates its own keyspace on startup — no manual schema setup needed:

| Service | Keyspace |
|---|---|
| fx-backend | `dola_fx` |
| fx-order-management-service | `dola_fx_oms` |
| fx-wallet-management-service | `dola_fx` |
| fx-ledger | `dola_fx_ledger` |
| fx-treasury | `dola_fx_treasury` |

Connect from host: `docker exec -it depot-cassandra cqlsh`

### Redpanda (`depot-redpanda`)

| Property | Value |
|---|---|
| Container name | `depot-redpanda` |
| Image | `redpandadata/redpanda:v24.1.9` |
| Container-to-container | `depot-redpanda:9092` (PLAINTEXT) |
| Host-side tools | `localhost:19092` (EXTERNAL) |

Topics are auto-created by services on first publish. Host-side inspection:
```bash
rpk --brokers localhost:19092 topic list
rpk --brokers localhost:19092 topic consume wallet.commands
```

### Network (`secure_idmsa_network`)

Created by `infra/docker-compose.yml` as a standard Docker bridge network. All other stacks reference it as `external: true`. depot-infra must be running before any other stack can start.

---

## Startup Ordering

The full dependency graph (enforced by Tilt `dc_resource(resource_deps=[])`):

```
depot-infra (cassandra + redpanda)
    │
    ├── odin (iam)
    │     ├── kratos-migrate → kratos_public / kratos_admin
    │     └── kratos_public → oathkeeper → traefik
    │
    ├── sync (etcd → sync)
    │
    ├── dola-backend (needs: cassandra, oathkeeper)
    │
    ├── fx-ledger (needs: cassandra)
    │
    ├── fx-wallet-management-service (needs: cassandra, redpanda, fx-ledger, sync)
    │
    ├── fx-order-management-service (needs: redpanda, fx-wallet-management-service)
    │
    └── fx-treasury (needs: cassandra, redpanda, fx-ledger, sync, fx-wallet-management-service)
```

`just up` calls `tilt up` which enforces this ordering with health-gating. Individual `just up-*` targets use docker compose directly with no health-gating — use them for targeted restarts only.

---

## Service URLs

| Service | URL | Swagger |
|---|---|---|
| fx-backend | http://localhost:8081 | http://localhost:8081/swagger-ui |
| fx-oms | http://localhost:8082 | http://localhost:8082/swagger-ui |
| fx-wms | http://localhost:8083 | http://localhost:8083/swagger-ui |
| fx-treasury | http://localhost:8084 | http://localhost:8084/swagger-ui |
| fx-ledger | http://localhost:8085 | http://localhost:8085/swagger-ui |
| sync | http://localhost:8090 | — |
| Tilt UI | http://localhost:10350 | — |
| Traefik UI | http://localhost:8080 | — |
| Jaeger | http://localhost:16686 | — |
| Mail (dev) | http://localhost:4436 | — |

---

## Adding a New Service

1. Add a `docker_compose()` call in `Tiltfile` with the correct `project_name`
2. Add `dc_resource('service-name', resource_deps=['dep1', 'dep2'])` entries for startup ordering
3. Add `up-<service>` / `down-<service>` targets to `justfile`
4. Add the service to the `status` and `health` targets in `justfile`
5. If the service needs Cassandra or Redpanda: point it at `depot-cassandra` / `depot-redpanda` — do not add per-service infra containers

---

## Relationship to Production

depot is local-only. Production uses:
- **Astra DB** (cloud Cassandra) instead of `depot-cassandra`
- **Hosted Redpanda** instead of `depot-redpanda`
- **Nomad** for service orchestration instead of Docker Compose
- **Vault** for secrets instead of `application-dev.yaml`

Deployment ordering in prod is handled by service-level retry logic and Nomad health checks — not by a depot equivalent.

---

## Known Issues & Gotchas

- **odin SMTP must be configured** — `../odin/.env.local` must have a real `SMTP_CONNECTION_URI` for email OTP flows to work. The placeholder `YOUR_APP_PASSWORD` will cause Kratos to fail silently on email sends.
- **Individual `just up-*` targets have no health-gating** — `docker compose up -d` does not wait for upstream services to be healthy. Use these only for targeted restarts when the rest of the stack is already running. For a full cold start, use `just up` (which calls `tilt up`).
- **amebo conflict** — `amebo/docker-compose.yml` previously conflicted with fx-backend (port 8081) and WMS Redpanda (port 9092). Remapped to host ports 18081, 18082, 29092. Do not start amebo while depot is running without checking for remaining conflicts.
- **Per-service `just stack-create` still works** — Individual services can still be started with their own `just stack-create` commands, but they require depot-infra to be running first (`cd depot && just up-infra`).
