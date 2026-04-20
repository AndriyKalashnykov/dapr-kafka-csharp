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

All Compose paths use Apache Kafka's official `apache/kafka` image (migrated off `bitnamilegacy/kafka` in 2026-04 — Bitnami paywalled production images; legacy namespace is a frozen archive). Both files use KRaft mode (no Zookeeper):
- **`docker-compose-kafka.yaml`** — single-broker, plaintext, auto-creates topics. The default for the demo. Image digest-pinned in the compose file itself.
- **`docker-compose.yaml`** — 3-node KRaft cluster, plaintext (downgraded from SASL+SSL in the migration). Image pinned via `KAFKA_IMAGE` in `.env` (digest-pinned). To use this topology, update Dapr component `brokers:` to `"localhost:9094,localhost:9095,localhost:9096"`.
- **K8s Helm** — `scripts/kafka.sh` installs the `bitnami/kafka` chart (v32.4.3, Kafka 4.0, SASL KRaft, provisioned topics). **Deferred migration**: the K8s path is still on `bitnamilegacy/kafka:4.0.0-debian-12-r10` (pinned via `BITNAMI_KAFKA_LEGACY_TAG` in Makefile). Needs switching to either Strimzi operator or a custom chart around `apache/kafka`. `KAFKA_CHART_VERSION` and `BITNAMI_KAFKA_LEGACY_TAG` are exported from Makefile to the script.

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

Tests are not yet present in the solution (`make test` silently reports zero assemblies). When added, they must use **TUnit** per the portfolio rule at `~/.claude/rules/dotnet/testing.md` (xUnit/NUnit/MSTest are migration-required). Preferred mocking library: **FakeItEasy**.

The Makefile exposes the three-layer test pyramid once tests exist:

| Target | Layer | Runtime |
|--------|-------|---------|
| `make test` | Unit (in-process, mocked deps) | seconds |
| `make integration-test` | Integration (Testcontainers, requires Docker) | seconds–tens of seconds |
| `make e2e` | End-to-end (KinD deploy + real message flow) | minutes |
| `make e2e-compose` | End-to-end (Docker Compose alternative) | minutes |

Run `/test-coverage-analysis` to scaffold missing test files.

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

- **Version manager**: mise (`.mise.toml`) — pins `dotnet`, `node`, `hadolint`, `act`, `dapr` CLI, `trivy`, `gitleaks`, `kind`, `cloud-provider-kind`, `kubectl`, `helm`. Single source of truth for CLI tooling.
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

Deferred items from `/upgrade-analysis` (2026-04-20). Review and resolve on future runs:

- [ ] **Helm 3 → 4 migration** — Helm 4.1.4 is stable alongside 3.20.2. Helm 4 has SDK/plugin API breaking changes. Pinned on `3.20.2` for now; plan a separate POC before committing.
- [ ] **K8s Kafka path still on Bitnami** — `scripts/kafka.sh` uses `bitnami/kafka` Helm chart with `bitnamilegacy/kafka:4.0.0-debian-12-r10`. Compose paths migrated to `apache/kafka` 2026-04; K8s path deferred. Options: (a) Strimzi operator, (b) custom chart around `apache/kafka`, (c) paid Broadcom Tanzu Bitnami registry. Track when Bitnami Helm chart itself moves behind the paywall.
- [ ] **Bitnami Helm chart succession** — `charts.bitnami.com/bitnami` moved to `repo.broadcom.com/bitnami-files` (302 redirect). If this host goes paywalled or offline, `scripts/kafka.sh` breaks. Monitor.

Resolved:

- [x] **Branch protection on `main`** — Repository Rulesets are active (discovered via direct-push rejection with `GH013: Repository rule violations found`); `ci-pass` is enforced as the required status check.
- [x] **Microsoft.NET.Test.Sdk ↔ TUnit 1.37.0 compat** — validated by green CI across runs [24689392397](https://github.com/AndriyKalashnykov/dapr-kafka-csharp/actions/runs/24689392397), [24690437810](https://github.com/AndriyKalashnykov/dapr-kafka-csharp/actions/runs/24690437810), and local `make ci-run` under act. TUnit bundles its own MTP runner; `Microsoft.NET.Test.Sdk` is not referenced in test csprojs.
- [x] **Kafka 4.2 upgrade** — Compose paths bumped to `apache/kafka:4.2.0` (digest-pinned); e2e-compose passes (PASS=2 FAIL=0). K8s path still on Bitnami — tracked separately.

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
