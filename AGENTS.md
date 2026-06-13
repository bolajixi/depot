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
├── Tiltfile                  — Tilt control plane: docker_compose() calls + resource_deps()
├── justfile                  — Fallback orchestration without Tilt
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

Tilt shows all service health, logs, and dependency state in a browser UI. It enforces the startup ordering defined in `Tiltfile` via `resource_deps()` — services will not start until their declared dependencies are healthy.

### Without Tilt (fallback)

```bash
cd depot
just up            # start everything in dependency order
just down          # stop everything (reverse order)
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

The full dependency graph (enforced by Tilt `resource_deps()`):

```
depot-infra (cassandra + redpanda)
    │
    ├── odin (iam)
    │     ├── kratos-migrate → kratos_public / kratos_admin
    │     ├── kratos_public → oathkeeper → traefik
    │     └── postgresd → hydra-migrate → hydra
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

When using `just up` (no Tilt), each target runs sequentially in this order. There is no health-gating between steps — if a service takes longer to start, the next `docker compose up -d` call still proceeds immediately. For guaranteed health-gated ordering, use `tilt up`.

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
2. Add `resource_deps()` entries declaring what must be healthy before this service starts
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
- **`just up` has no health-gating** — sequential `docker compose up -d` calls do not wait for the previous service to be healthy. If a service fails to connect to an upstream on startup, check `just logs <stack>` and restart that service after its dependency is ready.
- **amebo conflict** — `amebo/docker-compose.yml` previously conflicted with fx-backend (port 8081) and WMS Redpanda (port 9092). Remapped to host ports 18081, 18082, 29092. Do not start amebo while depot is running without checking for remaining conflicts.
- **Per-service `just stack-create` still works** — Individual services can still be started with their own `just stack-create` commands, but they require depot-infra to be running first (`cd depot && just up-infra`).
