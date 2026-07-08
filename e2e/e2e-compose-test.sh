#!/usr/bin/env bash
# E2E (Docker Compose alternative): start Kafka via docker-compose-kafka.yaml and run
# producer + consumer locally with Dapr sidecars. Lighter than the KinD path.
#
# Preconditions: Docker, Dapr CLI, .NET SDK installed. `make e2e-compose` invokes this
# after `docker compose up -d --wait`.
set -euo pipefail

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${WORKDIR}"

# Load committed defaults from .env.example (source of truth), then optional .env.
# shellcheck source=/dev/null
# `set -a` exports so ${VAR:-default} below picks up any override. Ephemeral ports
# are not used here (fixed compose/app ports), so sourcing is safe.
if [ -f .env.example ]; then set -a; . ./.env.example; set +a; fi
if [ -f .env         ]; then set -a; . ./.env;         set +a; fi
# Externalized e2e timing knobs (defaults mirror .env.example).
CONSUMER_START_WAIT_SECONDS="${CONSUMER_START_WAIT_SECONDS:-10}"
MSG_WAIT_SECONDS="${MSG_WAIT_SECONDS:-60}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-3}"
CURL_MAX_TIME_SECONDS="${CURL_MAX_TIME_SECONDS:-5}"

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
# The compose file's `up -d --wait` (invoked by `make e2e-compose`) already
# blocks until the kafka container reports Healthy via its HEALTHCHECK, so the
# broker is reachable by the time we reach this point. Print a confirmation
# probe via the canonical binary path (apache/kafka 4.x ships its scripts
# under /opt/kafka/bin/, not on $PATH) — fail loud if the broker disappears
# between `--wait` returning and this assertion.
if docker exec "$(docker compose -f docker-compose-kafka.yaml ps -q)" \
    /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 >/dev/null 2>&1; then
    echo "Kafka ready"
else
    echo "FAIL: Kafka broker unreachable despite compose reporting Healthy"
    exit 1
fi

section "Build solution once (before starting apps)"
# Build the whole solution up front so the consumer and producer are launched with
# `dotnet run --no-build`. Two concurrent `dotnet run` invocations in the same checkout
# otherwise race on MSBuild of the shared `models` project — both rewrite
# models/bin/Debug/net10.0/models.deps.json and the second build dies with
# "The process cannot access the file ... because it is being used by another process"
# (MSB4018 / GenerateDepsFile). Building once, then `--no-build`, removes the race
# deterministically. Config MUST be Debug so the pre-built output matches `dotnet run`'s
# default configuration.
dotnet build dapr-kafka-csharp.slnx -c Debug --nologo -v q
echo "Solution built"

section "Start consumer with Dapr sidecar"
(cd consumer && dapr run --app-id consumer --app-port 6000 --resources-path ../components --log-level warn -- dotnet run --no-build) \
    > "${LOG_CONSUMER}" 2>&1 &
PIDS+=($!)
# Give consumer + sidecar time to register subscription.
sleep "${CONSUMER_START_WAIT_SECONDS}"

section "Start producer with Dapr sidecar"
(cd producer && dapr run --app-id producer --resources-path ../components --log-level warn -- dotnet run --no-build) \
    > "${LOG_PRODUCER}" 2>&1 &
PIDS+=($!)

section "Wait for message flow (up to 60s)"
deadline=$(( $(date +%s) + MSG_WAIT_SECONDS ))
delivered=false
while [ "$(date +%s)" -lt "${deadline}" ]; do
    if grep -q "Message is delivered" "${LOG_CONSUMER}" 2>/dev/null; then
        delivered=true
        break
    fi
    sleep "${POLL_INTERVAL_SECONDS}"
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

section "Negative case — consumer rejects malformed POST to /sampletopic (mirrors KinD e2e)"
# The consumer is running locally via `dapr run --app-port 6000`; the app binds :6000
# directly. We curl that endpoint to verify the same status/Content-Type/ProblemDetails
# contract that the KinD e2e checks via the LoadBalancer.
headers="$(mktemp)"; body="$(mktemp)"
status="$(curl -s -o "${body}" -D "${headers}" -w '%{http_code}' --max-time "${CURL_MAX_TIME_SECONDS}" \
    -X POST "http://localhost:6000/sampletopic" \
    -H 'Content-Type: application/json' -d 'not-json' || echo "000")"

if [ "${status}" -ge 400 ] && [ "${status}" -lt 500 ]; then
    echo "PASS: malformed body returned ${status}"
    PASS=$((PASS + 1))
else
    echo "FAIL: malformed body returned ${status} (expected 4xx)"
    FAIL=$((FAIL + 1))
fi

content_type="$(awk 'tolower($1)=="content-type:"{$1=""; sub(/^[ \t]+/,""); print; exit}' "${headers}" | tr -d '\r')"
case "${content_type}" in
    application/problem+json*)
        echo "PASS: malformed-body response Content-Type='${content_type}'"
        PASS=$((PASS + 1))
        ;;
    *)
        echo "FAIL: malformed-body response Content-Type='${content_type}' (expected application/problem+json)"
        echo "--- raw headers ---"; cat "${headers}" || true
        FAIL=$((FAIL + 1))
        ;;
esac

if grep -qE '"status":\s*400' "${body}" && grep -qE '"title":\s*"Bad Request"' "${body}"; then
    echo "PASS: malformed-body response is RFC 7807 ProblemDetails"
    PASS=$((PASS + 1))
else
    echo "FAIL: malformed-body response missing ProblemDetails fields (status/title)"
    echo "--- body ---"; cat "${body}" || true
    FAIL=$((FAIL + 1))
fi
rm -f "${headers}" "${body}"

section "Results"
echo "PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
