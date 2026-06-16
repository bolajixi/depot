#!/usr/bin/env bash
# Platform-wide E2E test suite.
# Seeds a real user through the fx-backend registration + email verification
# flow, then runs all service hurl suites in dependency order.
#
# Run via:  just test-e2e
#       or: bash tests/e2e.sh
#
# Requires: full stack up (just up) + mailpit at localhost:8025.

set -euo pipefail

# ── Prerequisites ────────────────────────────────────────────────────────────
echo "Checking prerequisites..."
for port in 8081 8083 8082 8084 8085; do
  curl -sf "http://localhost:$port/actuator/health" >/dev/null 2>&1 \
    || { echo "Service on :$port is not up — run: just up"; exit 1; }
done
curl -sf "http://localhost:8025/api/v1/messages" >/dev/null 2>&1 \
  || { echo "Mail server not available at localhost:8025 — is odin stack up?"; exit 1; }

# ── Phase 1: Register ────────────────────────────────────────────────────────
TS=$(date +%s)
TEST_EMAIL="e2e-${TS}@dolafx-test.com"
echo ""
echo "Phase 1: Register ${TEST_EMAIL}"

_BODY=$(mktemp)
printf '{"method":"password","password":"HurlE2E123!","email":"%s","first_name":"E2E","last_name":"Test","phone_number":"+2348012345678"}' \
  "${TEST_EMAIL}" > "${_BODY}"
REGISTER=$(curl -sf -X POST http://localhost:8081/api/v1/auth/register \
  -H "Content-Type: application/json" -d "@${_BODY}")
rm -f "${_BODY}"

SESSION_TOKEN=$(echo "${REGISTER}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['sessionToken'])")
USER_ID=$(echo "${REGISTER}"       | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['userId'])")
echo "  userId=${USER_ID}  token=${SESSION_TOKEN:0:24}..."

# ── Phase 2: Verify email ────────────────────────────────────────────────────
echo ""
echo "Phase 2: Email verification"

_OTPBODY=$(mktemp)
printf '{"email":"%s"}' "${TEST_EMAIL}" > "${_OTPBODY}"
OTP_RESP=$(curl -sf -X POST http://localhost:8081/api/v1/auth/email-otp \
  -H "Content-Type: application/json" -d "@${_OTPBODY}")
rm -f "${_OTPBODY}"
FLOW_ID=$(echo "${OTP_RESP}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['flowId'])")

OTP_CODE=""
for i in $(seq 1 15); do
  sleep 2
  SEARCH=$(curl -sf "http://localhost:8025/api/v1/search?query=to:${TEST_EMAIL}&limit=1" 2>/dev/null || echo '{}')
  MSG_ID=$(echo "${SEARCH}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
msgs = d.get('messages', [])
print(msgs[0]['ID'] if msgs else '')
" 2>/dev/null || echo "")
  if [ -n "${MSG_ID}" ]; then
    BODY=$(curl -sf "http://localhost:8025/api/v1/message/${MSG_ID}" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Text',''))" 2>/dev/null || echo "")
    OTP_CODE=$(echo "${BODY}" | python3 -c "
import sys, re
m = re.search(r'\b([0-9]{6})\b', sys.stdin.read())
print(m.group(1) if m else '')
" 2>/dev/null || echo "")
    [ -n "${OTP_CODE}" ] && break
  fi
  echo "  Waiting for verification email (${i}/15)..."
done
[ -n "${OTP_CODE}" ] || { echo "Email verification timed out. Check http://localhost:8025"; exit 1; }
echo "  OTP received: ${OTP_CODE}"

_VBODY=$(mktemp)
printf '{"flow_id":"%s","code":"%s"}' "${FLOW_ID}" "${OTP_CODE}" > "${_VBODY}"
curl -sf -X POST http://localhost:8081/api/v1/auth/email-otp/verify \
  -H "Content-Type: application/json" -d "@${_VBODY}" >/dev/null
rm -f "${_VBODY}"
echo "  Email verified"

# ── Phase 3: fx-backend ──────────────────────────────────────────────────────
echo ""
echo "Phase 3: fx-backend API tests"
hurl --test --jobs 1 \
  --variable base_url=http://localhost:8081 \
  --variable ts="${TS}" \
  --variable session_token="${SESSION_TOKEN}" \
  ../fx-backend/tests/hurl/smoke.hurl \
  ../fx-backend/tests/hurl/auth.hurl \
  ../fx-backend/tests/hurl/callback.hurl \
  ../fx-backend/tests/hurl/user.hurl \
  ../fx-backend/tests/hurl/onboarding.hurl \
  ../fx-backend/tests/hurl/attachment.hurl \
  ../fx-backend/tests/hurl/admin.hurl

# ── Phase 4: WMS ─────────────────────────────────────────────────────────────
echo ""
echo "Phase 4: WMS tests"
hurl --test --jobs 1 \
  --variable base_url=http://localhost:8083 \
  --variable user_id="${USER_ID}" \
  ../fx-wallet-management-service/tests/hurl/smoke.hurl \
  ../fx-wallet-management-service/tests/hurl/wallet-create.hurl \
  ../fx-wallet-management-service/tests/hurl/wallet.hurl \
  ../fx-wallet-management-service/tests/hurl/idempotency.hurl \
  ../fx-wallet-management-service/tests/hurl/admin.hurl

WALLET_ACCOUNT_ID=$(curl -sf http://localhost:8083/api/v1/wallets/accounts \
  -H "X-User: ${USER_ID}" -H "X-User-ID: ${USER_ID}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['walletAccountId'])" 2>/dev/null || echo "")
echo "  wallet_account_id=${WALLET_ACCOUNT_ID}"

# ── Phase 5: OMS ─────────────────────────────────────────────────────────────
# wallet_account_id is the E2E user's EUR wallet from Phase 4.
# target_account_id reuses the same wallet (OMS validates UUID format only).
echo ""
echo "Phase 5: OMS tests"
TARGET_ACCOUNT_ID="${WALLET_ACCOUNT_ID:-00000000-0000-0000-0000-000000000001}"
hurl --test --jobs 1 \
  --variable base_url=http://localhost:8082 \
  --variable session_token="${SESSION_TOKEN}" \
  --variable user_id="${USER_ID}" \
  --variable wallet_account_id="${WALLET_ACCOUNT_ID:-00000000-0000-0000-0000-000000000001}" \
  --variable target_account_id="${TARGET_ACCOUNT_ID}" \
  ../fx-order-management-service/tests/hurl/smoke.hurl \
  ../fx-order-management-service/tests/hurl/oms.hurl

# ── Phase 6: Treasury ────────────────────────────────────────────────────────
echo ""
echo "Phase 6: Treasury tests"
hurl --test --jobs 1 \
  --variable base_url=http://localhost:8084 \
  --variable user_id="${USER_ID}" \
  ../fx-treasury/tests/hurl/smoke.hurl \
  ../fx-treasury/tests/hurl/treasury.hurl

# ── Phase 7: Ledger ──────────────────────────────────────────────────────────
echo ""
echo "Phase 7: Ledger tests"
hurl --test --jobs 1 \
  --variable base_url=http://localhost:8085 \
  --variable ts="${TS}" \
  ../fx-ledger/tests/hurl/smoke.hurl \
  ../fx-ledger/tests/hurl/ledger.hurl

echo ""
echo "E2E suite complete."
echo "  Session for ${TEST_EMAIL} is live in Kratos."
