# depot/justfile
# Local development control plane for the Dola FX platform.
#
# Usage:
#   just up          # start full stack via Tilt (dependency graph + UI at localhost:10350)
#   just down        # stop full stack via Tilt
#   just health      # hit /actuator/health on each service
#   just status      # running containers across all stacks
#   just urls        # print all service URLs
#
# Individual service targets use docker compose directly (for targeted restarts):
#   just up-wms / just down-wms   etc.

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

## Start full stack via Tilt (dependency graph + live UI at localhost:10350)
up:
    tilt up

## Stop full stack via Tilt
down:
    tilt down

## Nuke all containers + volumes (full reset)
nuke:
    tilt down
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
    @curl -sf http://localhost:8090/health          | python3 -c "import sys,json; d=json.load(sys.stdin); print('sync         ', 'UP' if d.get('etcd')=='ok' else 'DOWN')" 2>/dev/null || echo "sync          DOWN"

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
    @echo "  Mail UI      http://localhost:8025"
    @echo "  Cassandra    localhost:9042"
    @echo "  Redpanda     localhost:19092  (host-side tools)"
    @echo ""

# ── End-to-End Tests ───────────────────────────────────────────────────────
#
# Requires the full stack to be running (just up) including the odin IAM stack
# with mailpit available at http://localhost:8025.
#
# Flow:
#   1. Register a fresh timestamped user via fx-backend API → captures sessionToken + userId
#   2. Trigger email OTP via API → poll mailpit for the 6-digit code → verify email
#   3. Run fx-backend hurl suite (smoke, auth, callback, user, onboarding, attachment, admin)
#   4. Run WMS hurl suite (smoke, wallet-create, wallet, idempotency, admin)
#   5. Capture wallet_account_id from WMS for OMS
#   6. Run OMS smoke suite (full oms.hurl pending tasks #4 #5 #6)
#   7. Run treasury suite (smoke + treasury)
#   8. Run ledger smoke (ledger.hurl pending tasks #2 #3)
#
## Platform-wide E2E test suite — seeds a real user via APIs, tests all services
test-e2e:
    #!/usr/bin/env bash
    set -euo pipefail

    # ── Prerequisites ──────────────────────────────────────────────────────
    echo "Checking prerequisites..."
    for port in 8081 8083 8082 8084 8085; do
      curl -sf "http://localhost:$port/actuator/health" >/dev/null 2>&1 \
        || { echo "Service on :$port is not up — run: just up"; exit 1; }
    done
    curl -sf "http://localhost:8025/api/v1/messages" >/dev/null 2>&1 \
      || { echo "Mail server not available at localhost:8025 — is odin stack up?"; exit 1; }

    # ── Phase 1: Register ──────────────────────────────────────────────────
    TS=$(date +%s)
    TEST_EMAIL="e2e-$TS@dolafx-test.com"
    echo ""
    echo "Phase 1: Register $TEST_EMAIL"
    REGISTER=$(curl -sf -X POST http://localhost:8081/api/v1/auth/register \
      -H "Content-Type: application/json" \
      -d "{\"method\":\"password\",\"password\":\"HurlE2E123!\",\"email\":\"$TEST_EMAIL\",\
\"first_name\":\"E2E\",\"last_name\":\"Test\",\"phone_number\":\"+2348012345678\"}")
    SESSION_TOKEN=$(echo "$REGISTER" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['sessionToken'])")
    USER_ID=$(echo "$REGISTER"       | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['userId'])")
    echo "  userId=$USER_ID  token=${SESSION_TOKEN:0:24}..."

    # ── Phase 2: Verify email ──────────────────────────────────────────────
    echo ""
    echo "Phase 2: Email verification"
    OTP_RESP=$(curl -sf -X POST http://localhost:8081/api/v1/auth/email-otp \
      -H "Content-Type: application/json" \
      -d "{\"email\":\"$TEST_EMAIL\"}")
    FLOW_ID=$(echo "$OTP_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['flowId'])")

    OTP_CODE=""
    for i in $(seq 1 15); do
      sleep 2
      SEARCH=$(curl -sf "http://localhost:8025/api/v1/search?query=to:$TEST_EMAIL&limit=1" 2>/dev/null || echo '{}')
      MSG_ID=$(echo "$SEARCH" | python3 -c "
import sys,json
d=json.load(sys.stdin)
msgs=d.get('messages',[])
print(msgs[0]['ID'] if msgs else '')
" 2>/dev/null || echo "")
      if [ -n "$MSG_ID" ]; then
        BODY=$(curl -sf "http://localhost:8025/api/v1/message/$MSG_ID" \
          | python3 -c "import sys,json; print(json.load(sys.stdin).get('Text',''))" 2>/dev/null || echo "")
        OTP_CODE=$(echo "$BODY" | python3 -c "
import sys,re
m=re.search(r'\b([0-9]{6})\b',sys.stdin.read())
print(m.group(1) if m else '')
" 2>/dev/null || echo "")
        [ -n "$OTP_CODE" ] && break
      fi
      echo "  Waiting for verification email ($i/15)..."
    done
    [ -n "$OTP_CODE" ] || { echo "Email verification timed out. Check http://localhost:8025"; exit 1; }
    echo "  OTP received: $OTP_CODE"

    curl -sf -X POST http://localhost:8081/api/v1/auth/email-otp/verify \
      -H "Content-Type: application/json" \
      -d "{\"flow_id\":\"$FLOW_ID\",\"code\":\"$OTP_CODE\"}" >/dev/null
    echo "  Email verified"

    # ── Phase 3: fx-backend ────────────────────────────────────────────────
    echo ""
    echo "Phase 3: fx-backend API tests"
    hurl --test --jobs 1 \
      --variable base_url=http://localhost:8081 \
      --variable ts="$TS" \
      --variable session_token="$SESSION_TOKEN" \
      ../fx-backend/tests/hurl/smoke.hurl \
      ../fx-backend/tests/hurl/auth.hurl \
      ../fx-backend/tests/hurl/callback.hurl \
      ../fx-backend/tests/hurl/user.hurl \
      ../fx-backend/tests/hurl/onboarding.hurl \
      ../fx-backend/tests/hurl/attachment.hurl \
      ../fx-backend/tests/hurl/admin.hurl

    # ── Phase 4: WMS ──────────────────────────────────────────────────────
    echo ""
    echo "Phase 4: WMS tests"
    hurl --test --jobs 1 \
      --variable base_url=http://localhost:8083 \
      --variable user_id="$USER_ID" \
      ../fx-wallet-management-service/tests/hurl/smoke.hurl \
      ../fx-wallet-management-service/tests/hurl/wallet-create.hurl \
      ../fx-wallet-management-service/tests/hurl/wallet.hurl \
      ../fx-wallet-management-service/tests/hurl/idempotency.hurl \
      ../fx-wallet-management-service/tests/hurl/admin.hurl

    WALLET_ACCOUNT_ID=$(curl -sf http://localhost:8083/api/v1/wallets/accounts \
      -H "X-User: $USER_ID" -H "X-User-ID: $USER_ID" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['walletAccountId'])" 2>/dev/null || echo "")
    echo "  wallet_account_id=$WALLET_ACCOUNT_ID"

    # ── Phase 5: OMS (smoke only — oms.hurl pending tasks #4 #5 #6) ──────
    echo ""
    echo "Phase 5: OMS smoke tests  (oms.hurl skipped — pending fixes #4 #5 #6)"
    hurl --test --jobs 1 \
      --variable base_url=http://localhost:8082 \
      --variable user_id="$USER_ID" \
      ../fx-order-management-service/tests/hurl/smoke.hurl

    # ── Phase 6: Treasury ─────────────────────────────────────────────────
    echo ""
    echo "Phase 6: Treasury tests"
    hurl --test --jobs 1 \
      --variable base_url=http://localhost:8084 \
      --variable user_id="$USER_ID" \
      ../fx-treasury/tests/hurl/smoke.hurl \
      ../fx-treasury/tests/hurl/treasury.hurl

    # ── Phase 7: Ledger (smoke only — ledger.hurl pending tasks #2 #3) ───
    echo ""
    echo "Phase 7: Ledger smoke tests  (ledger.hurl skipped — pending fixes #2 #3)"
    hurl --test --jobs 1 \
      --variable base_url=http://localhost:8085 \
      ../fx-ledger/tests/hurl/smoke.hurl

    echo ""
    echo "E2E suite complete."
    echo "  Open sessions for $TEST_EMAIL are live in Kratos."
    echo "  Pending (tracked in task list): #2 #3 ledger bugs, #4 #5 #6 OMS bugs."

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
