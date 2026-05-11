# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dapr PubSub demo with Apache Kafka in C# (.NET 10). A **producer** console app publishes `SampleMessage` events to a Kafka topic via Dapr, and a **consumer** ASP.NET Core web app subscribes and processes them. Both share a **models** library.

## Build Commands

```bash
make build          # Build the solution
make clean          # Clean solution and remove bin/ and obj/ directories
make image-build    # Build Docker images for producer and consumer
make update         # Show outdated NuGet packages (via dotnet-outdated-tool)
make lint           # Check formatting, compiler warnings-as-errors, and lint Dockerfiles
make help           # List all available Makefile targets
```

The root-level `dapr-kafka-csharp.slnx` includes all three projects. Individual project builds:
```bash
dotnet build consumer/consumer.csproj
dotnet build producer/producer.csproj
dotnet build models/models.csproj
```

## Running Locally

```bash
# 1. Start Kafka (single-broker KRaft, no Zookeeper)
docker compose -f ./docker-compose-kafka.yaml up -d

# 2. Run consumer WITH Dapr sidecar (in one terminal)
cd consumer && dapr run --app-id consumer --app-port 6000 --resources-path ../components -- dotnet run
# or: make dapr-run-consumer

# 3. Run producer WITH Dapr sidecar (in another terminal)
cd producer && dapr run --app-id producer --resources-path ../components -- dotnet run
# or: make dapr-run-producer
```

`make dapr-run-consumer` and `make dapr-run-producer` invoke `dapr run` under the hood — they are NOT plain `dotnet run`. Without the sidecar, `PublishEventAsync` and the topic subscription do not work.

A 3-node KRaft Kafka cluster with SASL+SSL is available via `docker-compose.yaml` (advanced; requires Dapr component changes):
```bash
make local-kafka-run   # Start
make local-kafka-stop  # Stop
```

### Kafka Infrastructure

All Kafka paths run upstream Apache Kafka in KRaft mode (no Zookeeper). Bitnami was retired in 2026 after the production-image paywall:
- **`docker-compose-kafka.yaml`** — single-broker, plaintext, auto-creates topics. The default for the demo. Image digest-pinned to `apache/kafka:4.2.0` in the compose file itself.
- **`docker-compose.yaml`** — 3-node KRaft cluster, plaintext. Image pinned via `KAFKA_IMAGE` in `.env` (digest-pinned). To use this topology, update Dapr component `brokers:` to `"localhost:9094,localhost:9095,localhost:9096"`.
- **K8s** — `scripts/kafka.sh install` runs the Strimzi operator (`strimzi/strimzi-kafka-operator` chart, version pinned via `STRIMZI_OPERATOR_VERSION` in Makefile) and applies `k8s/strimzi-kafka.yaml` (`KafkaNodePool` + `Kafka` + `KafkaTopic` CRs — single-broker KRaft, plaintext). Strimzi pulls `quay.io/strimzi/kafka:<operator>-kafka-<spec.kafka.version>` automatically; bootstrap service for client traffic is `dapr-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092`.

## Architecture

```
producer/           Console app (Exe) - publishes SampleMessage every 10s
  Program.cs        DaprClient → PublishEventAsync("sampletopic", "sampletopic", ...)
  deploy/           Dapr component YAML for local standalone mode

consumer/           ASP.NET Core Web app - listens on port 6000
  Program.cs        Host builder, binds to http://*:6000
  Startup.cs        Configures Dapr, CloudEvents, MapPost("sampletopic") subscription
                    Topic filter: event.type == "com.dapr.event.sent"

models/             Shared library (net10.0, no dependencies)
  SampleMessage.cs  CorrelationId, MessageId, Message, CreationDate, Sentiment, PreviousAppTimestamp
```

- PubSub component name and topic name are both `"sampletopic"`
- Dapr component config: `components/kafka-pubsub.yaml` (shared by producer and consumer for local Compose) / `k8s/kafka-pubsub.yaml` (Kubernetes)
- Consumer uses `Startup.cs` pattern (not minimal API), with `UseCloudEvents()` middleware to unwrap CloudEvents payloads
- JSON serialization uses camelCase naming policy (`JsonNamingPolicy.CamelCase`)

## Kubernetes Deployment

Uses KinD + cloud-provider-kind (portfolio standard). cloud-provider-kind runs host-side and allocates LoadBalancer IPs on the `kind` Docker network; no in-cluster MetalLB.

```bash
# One-command stack up / down
make kind-up              # create cluster + start cloud-provider-kind + deploy Dapr + Kafka + workloads
make kind-down            # stop cloud-provider-kind and delete the cluster

# Granular
make kind-create          # create KinD cluster (image pinned via KIND_NODE_IMAGE, Renovate-tracked)
make kind-setup           # start cloud-provider-kind daemon (requires sudo for low-port bind)
make k8s-dapr-deploy      # install Dapr via Helm (chart v1.17.3)
make k8s-kafka-deploy     # install Kafka (Bitnami chart v32.4.3, Kafka 4.0, SASL)
make k8s-image-load       # build images and `kind load docker-image` into the cluster
make k8s-workload-deploy  # apply namespace + Dapr component + producer + consumer

# Verify
make k8s-test             # pods running, messages flowing end-to-end

# Teardown
make k8s-undeploy         # workloads + Kafka + Dapr + cluster
```

K8s manifests are in `k8s/` (namespace: `dapr-app`). `deps-k8s` checks for `kind`, `cloud-provider-kind`, `kubectl`, `helm`, and `dapr` (all mise-managed).

## Testing

Test projects live under `tests/` and use **TUnit 1.37.0** (portfolio rule at `~/.claude/rules/dotnet/testing.md` — xUnit/NUnit/MSTest are migration-required) with **FakeItEasy 9.0.1** for mocking:

| Project | Layer | Notes |
|---------|-------|-------|
| `tests/models.UnitTests` | Unit | Pure-data tests on `SampleMessage` |
| `tests/producer.UnitTests` | Unit | Mocks `DaprClient` via FakeItEasy |
| `tests/producer.IntegrationTests` | Integration | Real publish loop assertions |
| `tests/consumer.IntegrationTests` | Integration | `WebApplicationFactory<Program>` for in-process HTTP + CloudEvents |

The Makefile exposes the three-layer test pyramid:

| Target | Layer | Runtime |
|--------|-------|---------|
| `make test` | Unit (in-process, mocked deps) | seconds |
| `make integration-test` | Integration (Testcontainers where applicable, requires Docker) | seconds–tens of seconds |
| `make e2e` | End-to-end (KinD deploy + real message flow) | minutes |
| `make e2e-compose` | End-to-end (Docker Compose alternative) | minutes |

Run `/test-coverage-analysis` to find gaps and scaffold missing files.

## Formatting and Static Checks

```bash
make lint           # dotnet format --verify-no-changes + warnings-as-errors + hadolint
make format         # Auto-fix code formatting (dotnet format)
make static-check   # Composite: lint + vulncheck + secrets + trivy-fs + trivy-config + mermaid-lint + deps-prune-check
make vulncheck      # dotnet list package --vulnerable (CVE scan)
make secrets        # gitleaks scan
make trivy-fs       # Trivy filesystem scan (CRITICAL/HIGH)
make trivy-config   # Trivy config scan on k8s/
make mermaid-lint   # Parse every ```mermaid block via pinned minlag/mermaid-cli (same engine github.com uses)
```

`mermaid-lint` is wired into `static-check` because README embeds Mermaid C4 Context, Container, and Deployment diagrams — a broken block silently renders as a red "Unable to render rich display" box on the GitHub homepage. `MERMAID_CLI_VERSION` is pinned in the Makefile and Renovate-tracked.

## Key Details

- **Version manager**: mise (`.mise.toml`) — pins `dotnet`, `node`, `hadolint`, `act`, `dapr` CLI, `trivy`, `gitleaks`, `kind`, `cloud-provider-kind`, `kubectl`, `helm`. Single source of truth for CLI tooling. Tracked by Renovate's native `mise` manager (no `# renovate:` annotations needed in `.mise.toml`).
- **.NET SDK ↔ runtime mapping**: `global.json` pins SDK `10.0.203`, which maps to .NET runtime `10.0.7`. The Dockerfile uses the rolling tag `mcr.microsoft.com/dotnet/aspnet:10.0` digest-pinned; Renovate's `dockerfile` manager bumps the digest as Microsoft publishes newer 10.0.x runtimes. `rollForward: latestMajor` in `global.json` permits SDK/runtime drift across the 10.x line. Watch for drift in CI when SDK and runtime advance independently.
- **Dapr Dashboard Helm chart vs app version**: `make k8s-dapr-deploy` installs both `dapr/dapr` AND `dapr/dapr-dashboard` charts at version `$(DAPR_CHART_VERSION)`. The Dashboard's underlying `appVersion` (e.g., 0.15.0) tracks separately from the chart version. Renovate sees only the chart pin (via the DAPR_CHART_VERSION Makefile constant), not the app version. Bumping the app version requires a Dashboard-chart release that bundles the new app version.
- **K8s safety**: every `kubectl`/`helm` recipe is bound to `--context=kind-$(KIND_CLUSTER_NAME)` via the `KUBECTL` Makefile variable (and the `HELM_CTX` array in `scripts/kafka.sh`). Prevents cross-cluster bleed when other KinD-using projects rewrite `~/.kube/config` mid-session.
- **Namespaces** are sourced from `DAPR_APP_NS` (`dapr-app`) and `DAPR_SYSTEM_NS` (`dapr-system`) — single source of truth across all Makefile recipes.
- **Helm version**: Helm 4.x (`aqua:helm/helm = "4.1.4"` in `.mise.toml`). Helm 4 backward-compatibility for `apiVersion: v2` charts is good — both `dapr/dapr` and `strimzi/strimzi-kafka-operator` charts install cleanly under Helm 4 without code changes. We use only `repo add` / `repo update` / `upgrade --install` / `uninstall` / `ls`, all of which behave identically in v3 and v4. Helm 4's plugin SDK is a separate API surface from the CLI; the SDK-only breaking changes don't affect us. Renovate tracks via the mise manager.
- .NET SDK version pinned in `global.json` (10.0.201, `rollForward: latestMajor`, `allowPrerelease: true`)
- All projects target `net10.0`
- Each project has its own `nuget.config` pointing to NuGet v3 feed
- Docker images: both producer and consumer use `dotnet/aspnet:10.0` base (Dapr.AspNetCore requires ASP.NET runtime)
- `Directory.Build.props` enforces `TreatWarningsAsErrors` and `RestorePackagesWithLockFile` across all projects
- Renovate bot manages dependency updates (mise, NuGet, Dockerfiles, docker-compose, GitHub Actions, and inline `# renovate:` comments in Makefile / `.mise.toml`)

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on push to `main`, tag pushes (`v*`), and pull requests:

- `static-check` → gates everything downstream (format + warnings-as-errors + hadolint)
- `build`, `test`, `integration-test` run in parallel after `static-check` passes
- `e2e` runs after `build` + `test` (skipped when scaffolded e2e script is missing)
- On tag pushes (`v*`), a matrix `docker` job runs the full pre-push hardening pipeline:
  - Gate 1 — local single-arch build (`load: true`) with GHA cache
  - Gate 2 — Trivy image scan (CRITICAL/HIGH blocking, `scanners: vuln,secret,misconfig`)
  - Gate 3 — Smoke test (boot-marker grep: producer = `Publishing data:`, consumer = `Now listening on:` / `Application started`)
  - Gate 4 — Multi-arch build + push to GHCR (`linux/amd64`, `linux/arm64`, `provenance: false` + `sbom: false` Pattern A)
  - Gate 5 — Cosign keyless OIDC signing by digest (`id-token: write` required at job level)
- `ci-pass` aggregates all upstream jobs with `if: always()` — single required status check for branch protection

Local parity: `make docker-smoke-test` mirrors Gate 3.

The weekly cleanup workflow (`.github/workflows/cleanup-runs.yml`) prunes runs older than 7 days (keeping minimum 5) and prunes caches from closed pull-request branches.

## Upgrade Backlog

Deferred items waiting on upstream. Re-evaluate on each `/upgrade-analysis` pass.

- [ ] **kubectl 1.36 / kindest/node 1.36** — both are released, but `kind 0.31.0` still ships `kindest/node:v1.35.0` as its default. Bumping kubectl past 1.36 while the cluster is 1.35 creates a 1-minor skew (acceptable but uncomfortable). Trigger: when kind 0.32+ ships and defaults to v1.36. Renovate will PR the three independently — verify skew window before merging.

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
