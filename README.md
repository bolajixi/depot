# depot

Local development control plane for the Dola FX platform.

Depot owns the shared infrastructure (Cassandra, Redpanda, Docker network) that every `fx-*` service depends on, and provides health-gated startup ordering via [Tilt](https://tilt.dev). It also watches your source files — when you save a change, Tilt rebuilds and restarts only the affected service automatically, so you never have to leave your editor to redeploy.

---

## Required directory structure

Depot references sibling repos by relative path (`../fx-backend`, `../odin`, etc.). **All service repos must be cloned into the same parent directory.**

Clone each repo under a single `dola/` folder (or whatever you name it):

```
dola/
├── depot/                        ← this repo
├── odin/                         ← IAM (Kratos + Oathkeeper + Traefik)
├── sync/                         ← distributed lock service
├── fx-backend/
├── fx-ledger/
├── fx-wallet-management-service/
├── fx-order-management-service/
└── fx-treasury/
```

```bash
mkdir dola && cd dola

git clone https://github.com/dolapayments/depot
git clone https://github.com/dolapayments/odin
git clone https://github.com/dolapayments/sync
git clone https://github.com/dolapayments/fx-backend
git clone https://github.com/dolapayments/fx-ledger
git clone https://github.com/dolapayments/fx-wallet-management-service
git clone https://github.com/dolapayments/fx-order-management-service
git clone https://github.com/dolapayments/fx-treasury
```

If repos are not siblings of `depot/`, Tilt will fail to find the compose files on startup.

---

## Prerequisites

```bash
brew install tilt just
```

Docker Desktop must be running.

Set your SMTP credential for Ory Kratos (email OTP flows won't work without this):

```bash
# odin/.env.local
SMTP_CONNECTION_URI="smtps://you@gmail.com:YOUR_APP_PASSWORD@smtp.gmail.com:465/?skip_ssl_verify=true"
```

---

## Quickstart

```bash
cd dola/depot
tilt up
```

Tilt opens a browser UI at **http://localhost:10350** showing the health, logs, and build status of every service. Services start in dependency order — nothing starts until its upstream dependencies are healthy.

To stop everything:

```bash
tilt down
```

---

## Day-to-day commands

| Command | What it does |
|---|---|
| `just up` | Start full stack via Tilt |
| `just down` | Stop full stack via Tilt |
| `just health` | Hit `/actuator/health` on all services |
| `just status` | Show running containers across all stacks |
| `just urls` | Print all service URLs |
| `just logs <stack>` | Tail logs — stacks: `infra` `iam` `sync` `fx-backend` `fx-ledger` `wms` `oms` `treasury` |
| `just nuke` | Full reset: stop everything + delete all volumes |

### Targeted restarts (no Tilt required)

Use these when the rest of the stack is already up and you just want to restart one service:

```bash
just up-wms        # restart fx-wallet-management-service
just down-oms      # stop fx-order-management-service
just up-treasury   # restart fx-treasury
```

Available targets: `up/down-infra`, `up/down-iam`, `up/down-sync`, `up/down-fx-backend`, `up/down-fx-ledger`, `up/down-wms`, `up/down-oms`, `up/down-treasury`.

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
| Mail UI (dev) | http://localhost:4436 | — |

---

## Shared infrastructure

Depot runs one shared instance of each infra dependency, replacing the per-service containers that previously existed:

| Container | What it is | Host port |
|---|---|---|
| `depot-cassandra` | Cassandra 4.1 | `9042` |
| `depot-redpanda` | Redpanda (Kafka-compatible) | `19092` (host tools), `9092` (container-to-container) |
| `secure_idmsa_network` | Docker bridge network all services share | — |

Inspect Cassandra:
```bash
docker exec -it depot-cassandra cqlsh
```

Inspect Redpanda topics:
```bash
rpk --brokers localhost:19092 topic list
rpk --brokers localhost:19092 topic consume wallet.commands
```

---

## Startup ordering

Tilt enforces this dependency graph — no service starts until its upstream dependencies are healthy:

```
depot-infra (cassandra + redpanda + network)
    ├── odin (kratos-migrate → kratos → oathkeeper → traefik)
    ├── sync (etcd → sync)
    ├── fx-backend        (needs: cassandra, oathkeeper)
    ├── fx-ledger         (needs: cassandra)
    ├── fx-wms            (needs: cassandra, redpanda, fx-ledger, sync)
    ├── fx-oms            (needs: redpanda, fx-wms)
    └── fx-treasury       (needs: cassandra, redpanda, fx-ledger, sync, fx-wms)
```

---

## Keeping your local stack current

Each service repo is independent. When another team pushes changes, pull the relevant repo and Tilt will pick up the rebuild automatically if it's running, or on the next `tilt up`:

```bash
cd ../fx-wallet-management-service && git pull
cd ../fx-order-management-service  && git pull
# etc.
```

---

## Troubleshooting

**Tilt can't find a compose file** — check that all repos are cloned as siblings of `depot/` (see directory structure above).

**Email OTP not working** — `odin/.env.local` must have a real `SMTP_CONNECTION_URI`. The placeholder causes Kratos to fail silently.

**Port conflict on startup** — run `just status` to see what's already running. `just nuke` does a full reset if you need a clean slate.

**Individual `just up-*` targets have no health-gating** — `docker compose up -d` doesn't wait for upstream services. Use these only for targeted restarts when the rest of the stack is already healthy. For a cold start always use `just up`.
