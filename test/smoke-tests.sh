#!/usr/bin/env bash
set -uo pipefail
cd /sessions/brave-bold-euler/work
export CDS_ENV=development
export CDS_REQUIRES_AUTH_KIND=dummy
B="http://localhost:4004"
# reset seed data for deterministic quotas
node node_modules/@sap/cds-dk/bin/cds.js deploy --to sqlite:db/entitlements.db >/tmp/deploy.log 2>&1 && echo "### redeployed fresh seed"
rm -f server.log
node node_modules/@sap/cds-dk/bin/cds.js serve all --port 4004 > server.log 2>&1 &
SRV=$!
for i in $(seq 1 40); do
  grep -qiE "server listening" server.log 2>/dev/null && break
  kill -0 $SRV 2>/dev/null || { echo "SERVER DIED"; cat server.log; exit 1; }
  sleep 1
done
echo "### SERVER UP after ${i}s"
E3="22222222-2222-2222-2222-222222222203"   # object-store quota 100, seeded consumed 40, remaining 60
E5="22222222-2222-2222-2222-222222222205"   # ai-core SUSPENDED
hr(){ echo; echo "===== $1 ====="; }

hr "A. Bound action recordConsumption WITHIN quota (E3 remaining 60, book 30) -> expect 200/201, remaining 30"
curl -s -X POST "$B/odata/v4/entitlement/Entitlements(ID=$E3,IsActiveEntity=true)/EntitlementService.recordConsumption" \
  -H "Content-Type: application/json" \
  -d '{"amount":30,"usageDate":"2025-05-01","region":"us10","note":"action within quota"}' \
  -w "\nHTTP %{http_code}\n"

hr "B. Bound action recordConsumption EXCEEDING quota (E3 remaining 30, book 500) -> expect 409"
curl -s -X POST "$B/odata/v4/entitlement/Entitlements(ID=$E3,IsActiveEntity=true)/EntitlementService.recordConsumption" \
  -H "Content-Type: application/json" \
  -d '{"amount":500,"usageDate":"2025-05-02","note":"action over quota"}' \
  -w "\nHTTP %{http_code}\n"

hr "C. REST POST Consumptions WITHIN quota (E3 remaining 30, book 20) -> expect 201, remaining 10"
curl -s -X POST "$B/rest/entitlement/Consumptions" \
  -H "Content-Type: application/json" \
  -d "{\"entitlement_ID\":\"$E3\",\"amount\":20,\"usageDate\":\"2025-06-01\",\"note\":\"rest within quota\"}" \
  -w "\nHTTP %{http_code}\n"

hr "D. REST POST Consumptions EXCEEDING quota (E3 remaining 10, book 50) -> expect 409"
curl -s -X POST "$B/rest/entitlement/Consumptions" \
  -H "Content-Type: application/json" \
  -d "{\"entitlement_ID\":\"$E3\",\"amount\":50,\"usageDate\":\"2025-06-02\"}" \
  -w "\nHTTP %{http_code}\n"

hr "E. REST POST bad date (before validFrom 2025-03-01) -> expect 400"
curl -s -X POST "$B/rest/entitlement/Consumptions" \
  -H "Content-Type: application/json" \
  -d "{\"entitlement_ID\":\"$E3\",\"amount\":1,\"usageDate\":\"2020-01-01\"}" \
  -w "\nHTTP %{http_code}\n"

hr "F. REST POST to SUSPENDED entitlement (E5) -> expect 409"
curl -s -X POST "$B/rest/entitlement/Consumptions" \
  -H "Content-Type: application/json" \
  -d "{\"entitlement_ID\":\"$E5\",\"amount\":10,\"usageDate\":\"2025-06-20\"}" \
  -w "\nHTTP %{http_code}\n"

hr "G. REST POST negative amount -> expect 400"
curl -s -X POST "$B/rest/entitlement/Consumptions" \
  -H "Content-Type: application/json" \
  -d "{\"entitlement_ID\":\"$E3\",\"amount\":-5,\"usageDate\":\"2025-06-03\"}" \
  -w "\nHTTP %{http_code}\n"

hr "H. Final read E3 remaining quota (started 60, booked 30+20=50 -> remaining 10)"
curl -s "$B/odata/v4/entitlement/Entitlements(ID=$E3,IsActiveEntity=true)?\$select=subaccount,quota,consumedQuota,remainingQuota" -w "\nHTTP %{http_code}\n"

hr "I. Entitlement create date-range validation (validFrom after validTo) via REST -> expect 400"
curl -s -X POST "$B/rest/entitlement/Entitlements" \
  -H "Content-Type: application/json" \
  -d "{\"subaccount\":\"sub-x\",\"product_ID\":\"11111111-1111-1111-1111-111111111101\",\"plan\":\"standard\",\"quota\":10,\"unit\":\"GB\",\"validFrom\":\"2025-12-31\",\"validTo\":\"2025-01-01\"}" \
  -w "\nHTTP %{http_code}\n"

kill $SRV 2>/dev/null; wait $SRV 2>/dev/null; echo "### DONE"
