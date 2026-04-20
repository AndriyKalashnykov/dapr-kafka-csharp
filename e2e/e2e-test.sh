#!/usr/bin/env bash
# E2E: KinD-based Dapr pub/sub round-trip.
#
# Preconditions: `make kind-up` has deployed the full stack (KinD + cloud-provider-kind +
# Dapr + Kafka + producer + consumer). This script asserts the cross-service message flow.
set -euo pipefail

NS="${NS:-dapr-app}"
TIMEOUT="${TIMEOUT:-120s}"
PASS=0
FAIL=0

section() { printf '\n\033[36m=== %s ===\033[0m\n' "$1"; }

assert_true() {
    local desc="$1"
    if eval "${2}" >/dev/null 2>&1; then
        echo "PASS: ${desc}"
        PASS=$((PASS + 1))
    else
        echo "FAIL: ${desc}"
        FAIL=$((FAIL + 1))
    fi
}

section "Wait for pods Ready"
kubectl wait --namespace="${NS}" --for=condition=ready pod --selector=app=producer --timeout="${TIMEOUT}"
kubectl wait --namespace="${NS}" --for=condition=ready pod --selector=app=consumer --timeout="${TIMEOUT}"

section "Assert Dapr sidecars injected"
assert_true "producer has dapr sidecar" "kubectl get pods -n '${NS}' -l app=producer -o jsonpath='{.items[0].spec.containers[*].name}' | grep -qw daprd"
assert_true "consumer has dapr sidecar" "kubectl get pods -n '${NS}' -l app=consumer -o jsonpath='{.items[0].spec.containers[*].name}' | grep -qw daprd"

section "Wait for pub/sub round-trip — producer publishes every 10s"
echo "Collecting consumer logs for up to 60s..."
deadline=$(( $(date +%s) + 60 ))
delivered=false
while [ "$(date +%s)" -lt "${deadline}" ]; do
    if kubectl logs -l app=consumer -c consumer -n "${NS}" --tail=200 2>/dev/null | grep -q "Message is delivered"; then
        delivered=true
        break
    fi
    sleep 3
done

if [ "${delivered}" = "true" ]; then
    echo "PASS: consumer received a message from Kafka via Dapr"
    PASS=$((PASS + 1))
else
    echo "FAIL: no message delivered within 60s"
    echo "--- consumer logs ---"
    kubectl logs -l app=consumer -c consumer -n "${NS}" --tail=50 || true
    echo "--- producer logs ---"
    kubectl logs -l app=producer -c producer -n "${NS}" --tail=50 || true
    FAIL=$((FAIL + 1))
fi

section "Assert message content is parsed (correlationId or messageId log line)"
assert_true "consumer logged a message id" "kubectl logs -l app=consumer -c consumer -n '${NS}' --tail=200 | grep -qE 'message id:'"

section "Assert continuous delivery — expect >=2 messages within 30s"
deadline=$(( $(date +%s) + 30 ))
count=0
while [ "$(date +%s)" -lt "${deadline}" ]; do
    count="$(kubectl logs -l app=consumer -c consumer -n "${NS}" --tail=500 2>/dev/null | grep -c "Message is delivered" || true)"
    if [ "${count}" -ge 2 ]; then
        break
    fi
    sleep 3
done
assert_true "at least 2 messages delivered (got ${count})" "[ '${count}' -ge 2 ]"

section "Negative case — consumer rejects malformed POST to /sampletopic"
gateway_ip="$(kubectl get svc -n "${NS}" consumer -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
if [ -n "${gateway_ip}" ]; then
    status="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://${gateway_ip}/sampletopic" \
        -H 'Content-Type: application/json' -d 'not-json' || echo "000")"
    if [ "${status}" -ge 400 ] && [ "${status}" -lt 500 ]; then
        echo "PASS: malformed body returned ${status}"
        PASS=$((PASS + 1))
    else
        echo "FAIL: malformed body returned ${status} (expected 4xx)"
        FAIL=$((FAIL + 1))
    fi
else
    echo "SKIP: LoadBalancer IP not available — cloud-provider-kind not running?"
fi

section "Results"
echo "PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
