#!/usr/bin/env bash
# E2E (Docker Compose alternative): start Kafka via docker-compose-kafka.yaml and run
# producer + consumer locally with Dapr sidecars. Lighter than the KinD path.
#
# Preconditions: Docker, Dapr CLI, .NET SDK installed. `make e2e-compose` invokes this
# after `docker compose up -d --wait`.
set -euo pipefail

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${WORKDIR}"

PASS=0
FAIL=0
LOG_CONSUMER="/tmp/consumer.log"
LOG_PRODUCER="/tmp/producer.log"
PIDS=()

section() { printf '\n\033[36m=== %s ===\033[0m\n' "$1"; }

cleanup() {
    for pid in "${PIDS[@]:-}"; do
        kill "${pid}" 2>/dev/null || true
    done
    # dapr run leaves background sidecars — best-effort cleanup.
    dapr stop --app-id producer 2>/dev/null || true
    dapr stop --app-id consumer 2>/dev/null || true
}
trap cleanup EXIT

section "Preflight"
command -v dapr >/dev/null || { echo "Error: dapr CLI required"; exit 1; }
command -v dotnet >/dev/null || { echo "Error: dotnet SDK required"; exit 1; }

section "Wait for Kafka broker"
for _ in $(seq 1 30); do
    if docker exec "$(docker compose -f docker-compose-kafka.yaml ps -q)" \
        kafka-broker-api-versions.sh --bootstrap-server localhost:9092 >/dev/null 2>&1; then
        echo "Kafka ready"
        break
    fi
    sleep 2
done

section "Start consumer with Dapr sidecar"
(cd consumer && dapr run --app-id consumer --app-port 6000 --resources-path ../components --log-level warn -- dotnet run) \
    > "${LOG_CONSUMER}" 2>&1 &
PIDS+=($!)
# Give consumer + sidecar time to register subscription.
sleep 10

section "Start producer with Dapr sidecar"
(cd producer && dapr run --app-id producer --resources-path ../components --log-level warn -- dotnet run) \
    > "${LOG_PRODUCER}" 2>&1 &
PIDS+=($!)

section "Wait for message flow (up to 60s)"
deadline=$(( $(date +%s) + 60 ))
delivered=false
while [ "$(date +%s)" -lt "${deadline}" ]; do
    if grep -q "Message is delivered" "${LOG_CONSUMER}" 2>/dev/null; then
        delivered=true
        break
    fi
    sleep 3
done

if [ "${delivered}" = "true" ]; then
    echo "PASS: consumer received a message via Dapr pub/sub over docker-compose Kafka"
    PASS=$((PASS + 1))
else
    echo "FAIL: no message delivered within 60s"
    echo "--- consumer log (tail) ---"
    tail -n 30 "${LOG_CONSUMER}" || true
    echo "--- producer log (tail) ---"
    tail -n 30 "${LOG_PRODUCER}" || true
    FAIL=$((FAIL + 1))
fi

section "Assert producer logged at least one publish"
if grep -qE "Publishing data" "${LOG_PRODUCER}" 2>/dev/null; then
    echo "PASS: producer logged publish"
    PASS=$((PASS + 1))
else
    echo "FAIL: producer did not log any publish"
    FAIL=$((FAIL + 1))
fi

section "Results"
echo "PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
