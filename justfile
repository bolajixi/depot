# depot/justfile
# Local development control plane — fallback for environments without Tilt.
# Prefer `tilt up` for the full experience (dependency graph + live UI).
#
# Usage:
#   just up          # start everything in the correct order
#   just down        # stop everything
#   just status      # show running containers across all stacks
#   just health      # hit /actuator/health on each service
#   just urls        # print all service URLs

default:
    just --list

# ── Infrastructure ─────────────────────────────────────────────────────────

up-infra:
    docker compose -p depot-infra -f infra/docker-compose.yml up -d

down-infra:
    docker compose -p depot-infra -f infra/docker-compose.yml down

# ── IAM ────────────────────────────────────────────────────────────────────

up-iam:
    docker compose --env-file ../odin/.env.local -p odin-secure-stack -f ../odin/docker-compose.yml up -d

down-iam:
    docker compose --env-file ../odin/.env.local -p odin-secure-stack -f ../odin/docker-compose.yml down

# ── Sync ───────────────────────────────────────────────────────────────────

up-sync:
    docker compose -p sync-stack -f ../sync/docker-compose.yml up -d

down-sync:
    docker compose -p sync-stack -f ../sync/docker-compose.yml down

# ── Application Services ───────────────────────────────────────────────────

up-fx-backend:
    docker compose -p dola-backend-stack -f ../fx-backend/docker-compose.yml up -d

down-fx-backend:
    docker compose -p dola-backend-stack -f ../fx-backend/docker-compose.yml down

up-fx-ledger:
    docker compose -p fx-ledger-stack -f ../fx-ledger/docker-compose.yaml up -d

down-fx-ledger:
    docker compose -p fx-ledger-stack -f ../fx-ledger/docker-compose.yaml down

up-wms:
    docker compose -p fx-wallet-management-stack -f ../fx-wallet-management-service/docker-compose.yml up -d

down-wms:
    docker compose -p fx-wallet-management-stack -f ../fx-wallet-management-service/docker-compose.yml down

up-oms:
    docker compose -p fx-order-management-stack -f ../fx-order-management-service/docker-compose.yml up -d

down-oms:
    docker compose -p fx-order-management-stack -f ../fx-order-management-service/docker-compose.yml down

up-treasury:
    docker compose -p fx-treasury-stack -f ../fx-treasury/docker-compose.yml up -d

down-treasury:
    docker compose -p fx-treasury-stack -f ../fx-treasury/docker-compose.yml down

# ── Full Stack ─────────────────────────────────────────────────────────────

## Start everything in dependency order
up: up-infra up-iam up-sync up-fx-backend up-fx-ledger up-wms up-oms up-treasury

## Stop everything (reverse order)
down: down-treasury down-oms down-wms down-fx-ledger down-fx-backend down-sync down-iam down-infra

## Nuke all containers + volumes (full reset)
nuke:
    just down
    docker compose -p depot-infra -f infra/docker-compose.yml down -v
    docker network rm secure_idmsa_network 2>/dev/null || true

# ── Observability ──────────────────────────────────────────────────────────

## Running containers across all stacks
status:
    @echo "=== infra ===";       docker compose -p depot-infra              -f infra/docker-compose.yml                                        ps 2>/dev/null || true
    @echo "=== iam ===";         docker compose -p odin-secure-stack         -f ../odin/docker-compose.yml                                      ps 2>/dev/null || true
    @echo "=== sync ===";        docker compose -p sync-stack                -f ../sync/docker-compose.yml                                      ps 2>/dev/null || true
    @echo "=== fx-backend ===";  docker compose -p dola-backend-stack        -f ../fx-backend/docker-compose.yml                                ps 2>/dev/null || true
    @echo "=== fx-ledger ===";   docker compose -p fx-ledger-stack           -f ../fx-ledger/docker-compose.yaml                                ps 2>/dev/null || true
    @echo "=== wms ===";         docker compose -p fx-wallet-management-stack -f ../fx-wallet-management-service/docker-compose.yml             ps 2>/dev/null || true
    @echo "=== oms ===";         docker compose -p fx-order-management-stack  -f ../fx-order-management-service/docker-compose.yml              ps 2>/dev/null || true
    @echo "=== treasury ===";    docker compose -p fx-treasury-stack          -f ../fx-treasury/docker-compose.yml                              ps 2>/dev/null || true

## Hit /actuator/health on each application service
health:
    @curl -sf http://localhost:8081/actuator/health | python3 -c "import sys,json; d=json.load(sys.stdin); print('fx-backend   ', d['status'])" 2>/dev/null || echo "fx-backend    DOWN"
    @curl -sf http://localhost:8082/actuator/health | python3 -c "import sys,json; d=json.load(sys.stdin); print('fx-oms       ', d['status'])" 2>/dev/null || echo "fx-oms        DOWN"
    @curl -sf http://localhost:8083/actuator/health | python3 -c "import sys,json; d=json.load(sys.stdin); print('fx-wms       ', d['status'])" 2>/dev/null || echo "fx-wms        DOWN"
    @curl -sf http://localhost:8084/actuator/health | python3 -c "import sys,json; d=json.load(sys.stdin); print('fx-treasury  ', d['status'])" 2>/dev/null || echo "fx-treasury   DOWN"
    @curl -sf http://localhost:8085/actuator/health | python3 -c "import sys,json; d=json.load(sys.stdin); print('fx-ledger    ', d['status'])" 2>/dev/null || echo "fx-ledger     DOWN"
    @curl -sf http://localhost:8090/health          | python3 -c "import sys,json; d=json.load(sys.stdin); print('sync         ', d['status'])" 2>/dev/null || echo "sync          DOWN"

## Print all service URLs
urls:
    @echo ""
    @echo "Application Services"
    @echo "  fx-backend   http://localhost:8081   swagger: http://localhost:8081/swagger-ui"
    @echo "  fx-oms       http://localhost:8082   swagger: http://localhost:8082/swagger-ui"
    @echo "  fx-wms       http://localhost:8083   swagger: http://localhost:8083/swagger-ui"
    @echo "  fx-treasury  http://localhost:8084   swagger: http://localhost:8084/swagger-ui"
    @echo "  fx-ledger    http://localhost:8085   swagger: http://localhost:8085/swagger-ui"
    @echo "  sync         http://localhost:8090"
    @echo ""
    @echo "Infrastructure"
    @echo "  Traefik UI   http://localhost:8080"
    @echo "  Jaeger       http://localhost:16686"
    @echo "  Mail UI      http://localhost:4436"
    @echo "  Cassandra    localhost:9042"
    @echo "  Redpanda     localhost:19092  (host-side tools)"
    @echo ""

## Tail logs — usage: just logs <stack> [service]
## Stacks: infra, iam, sync, fx-backend, fx-ledger, wms, oms, treasury
logs stack service="":
    #!/usr/bin/env bash
    set -e
    case "{{stack}}" in
      infra)       f="infra/docker-compose.yml";                                      p="depot-infra" ;;
      iam|odin)    f="../odin/docker-compose.yml";                                    p="odin-secure-stack" ;;
      sync)        f="../sync/docker-compose.yml";                                    p="sync-stack" ;;
      fx-backend)  f="../fx-backend/docker-compose.yml";                              p="dola-backend-stack" ;;
      fx-ledger)   f="../fx-ledger/docker-compose.yaml";                              p="fx-ledger-stack" ;;
      wms)         f="../fx-wallet-management-service/docker-compose.yml";            p="fx-wallet-management-stack" ;;
      oms)         f="../fx-order-management-service/docker-compose.yml";             p="fx-order-management-stack" ;;
      treasury)    f="../fx-treasury/docker-compose.yml";                             p="fx-treasury-stack" ;;
      *) echo "Unknown stack: {{stack}}. Options: infra iam sync fx-backend fx-ledger wms oms treasury"; exit 1 ;;
    esac
    if [ -z "{{service}}" ]; then
      docker compose -p "$p" -f "$f" logs -f
    else
      docker compose -p "$p" -f "$f" logs -f "{{service}}"
    fi
