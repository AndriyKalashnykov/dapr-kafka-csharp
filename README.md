[![CI](https://github.com/AndriyKalashnykov/dapr-kafka-csharp/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/dapr-kafka-csharp/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/dapr-kafka-csharp.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/dapr-kafka-csharp/)
[![.NET](https://img.shields.io/badge/.NET-10.0-512BD4?logo=dotnet)](https://dotnet.microsoft.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/dapr-kafka-csharp)

# Dapr Pub/Sub on Apache Kafka — .NET 10 Reference

Two services — a console producer and an ASP.NET Core consumer — exchange `SampleMessage` events through Dapr sidecars backed by Apache Kafka. The consumer uses Dapr's CloudEvents middleware to unwrap payloads and filters on `event.type == com.dapr.event.sent`.

Runs locally via Docker Compose (`apache/kafka`) or on Kubernetes via KinD + cloud-provider-kind (Bitnami Helm chart for the broker). The test pyramid covers three layers on TUnit + FakeItEasy: unit (in-process, mocked), integration (Testcontainers), and end-to-end (Compose or KinD). The tag-triggered release pipeline Trivy-scans the image, smoke-tests it via boot-marker grep, publishes multi-arch (amd64/arm64) to GHCR, and cosign-signs by digest.

```mermaid
C4Context
    title System Context — Dapr Kafka PubSub Demo
    Person(operator, "Operator", "Developer or CI running the demo locally or on KinD")
    System(dkc, "Dapr Kafka PubSub", "Pub/sub demo decoupling .NET producer and consumer from Kafka via Dapr sidecars")
    System_Ext(kafka, "Apache Kafka", "External message broker (4.0.2 local / 4.0.0 K8s)")
    Rel(operator, dkc, "Runs", "make dapr-run-* / kind-up")
    Rel(dkc, kafka, "Publishes / subscribes via Dapr sidecar", "Kafka protocol")
```

## Tech Stack

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Language | C# on .NET 10 (`10.0.201` via `global.json`) | LTS through 2028-11; matches Dapr.AspNetCore 10 support matrix |
| Runtime image | `mcr.microsoft.com/dotnet/aspnet:10.0` | Required by Dapr.AspNetCore (pulls in ASP.NET runtime) |
| Dapr SDK | `Dapr.AspNetCore`, `Dapr.Client` | Idiomatic sidecar integration with CloudEvents unwrapping |
| Dapr CLI | 1.17.1 (mise-pinned) | Runtime chart is 1.17.5 via `DAPR_CHART_VERSION`; CLI and runtime version independently |
| Message broker | Apache Kafka 4.x — 4.0.2 (Compose) / 4.0.0 (K8s) | No Zookeeper; `apache/kafka` official image for local Compose; Bitnami Helm chart on `bitnamilegacy/kafka:4.0.0-debian-12-r10` for K8s (migration deferred) |
| PubSub component | `sampletopic` (pubsub.kafka) | Topic name and component name match by convention |
| Container tooling | Docker + Buildx (multi-arch amd64/arm64) | ARM64 coverage for Apple Silicon and Graviton |
| Kubernetes | KinD + cloud-provider-kind + Dapr Helm chart | Kind-team maintained, single Docker network, host-side LoadBalancer daemon |
| Version manager | mise (aqua backend) | Single source of truth for CLI tooling versions |
| CI/CD | GitHub Actions + Renovate | Platform automerge; SHA-pinned actions; GHCR publishing on tag |

## Quick Start

```bash
make deps                    # bootstrap mise, install CLI toolchain
make build                   # build the solution
docker compose -f ./docker-compose-kafka.yaml up -d   # start Kafka
make dapr-run-consumer       # run consumer with Dapr sidecar (terminal 1)
make dapr-run-producer       # run producer with Dapr sidecar (terminal 2)
```

The `dapr-run-*` targets invoke `dapr run --app-id ... -- dotnet run`. Without the sidecar, `PublishEventAsync` and the topic subscription do not work.

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Git](https://git-scm.com/) | 2.x+ | Version control |
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+ | Build orchestration |
| [mise](https://mise.jdx.dev/) | latest | Installs the CLI toolchain (hadolint, act, dapr, trivy, gitleaks) per `.mise.toml` |
| [.NET SDK](https://dotnet.microsoft.com/download) | 10.0.201 (from `global.json`) | Build and run C# projects |
| [Docker](https://www.docker.com/) | latest | Run Kafka locally, build container images |
| [Dapr CLI](https://docs.dapr.io/getting-started/install-dapr-cli/) | 1.17.1 (mise-pinned) | Run Dapr sidecars locally |
| [KinD](https://kind.sigs.k8s.io/) | 0.31.0 (mise-pinned) | Local Kubernetes cluster (for `make kind-up`) |
| [cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind) | 0.10.0 (mise-pinned) | LoadBalancer controller for KinD (allocates IPs on the `kind` Docker network) |
| [Helm](https://helm.sh/) | latest | Deploy Dapr/Kafka to Kubernetes (optional) |

Install CLI tooling via mise:

```bash
make deps      # runs `mise install` (no sudo; installs to $HOME/.local/share/mise)
```

## Architecture

### Container View

```mermaid
C4Container
    title Container View — Dapr sidecar pattern
    Person(operator, "Operator")
    System_Boundary(app, "Dapr Kafka PubSub") {
        Container(producer, "Producer", ".NET 10 console, Dapr.Client 1.17.9", "Publishes SampleMessage every 10s")
        Container(producer_dapr, "Dapr Sidecar", "daprd 1.17, injected at deploy-time", "Produces to Kafka via pubsub component")
        Container(consumer, "Consumer", ".NET 10, ASP.NET Core, Dapr.AspNetCore 1.17.9", "Handles POST /sampletopic on :6000")
        Container(consumer_dapr, "Dapr Sidecar", "daprd 1.17, injected at deploy-time", "Subscribes to Kafka, delivers CloudEvents")
    }
    ContainerDb(kafka, "Kafka", "Apache Kafka 4.x (KRaft)", "Topic: sampletopic")
    Rel(operator, producer, "dapr run / make dapr-run-producer")
    Rel(operator, consumer, "dapr run / make dapr-run-consumer")
    Rel(producer, producer_dapr, "PublishEventAsync", "HTTP/gRPC to :3500/:50001")
    Rel(producer_dapr, kafka, "Produce", "Kafka protocol")
    Rel(kafka, consumer_dapr, "Consume", "Kafka protocol")
    Rel(consumer_dapr, consumer, "POST /sampletopic", "HTTP + CloudEvents envelope")
```

- **Producer** is a .NET 10 console app in an infinite loop — generates a `SampleMessage` every 10s and calls `DaprClient.PublishEventAsync("sampletopic", "sampletopic", message)`. Never talks to Kafka directly.
- **Dapr sidecars** are the architectural point: the app sees only HTTP/gRPC to `localhost`; the sidecar owns Kafka connection, serialization, retries, and observability. Pub/sub component config: `components/kafka-pubsub.yaml` (shared by both apps for local Compose) / `k8s/kafka-pubsub.yaml` (Kubernetes).
- **Consumer** uses the legacy `Startup.cs` pattern with `UseCloudEvents()` to unwrap the CloudEvents envelope that the sidecar wraps around delivered messages. `MapPost("sampletopic").WithTopic(...)` registers the subscription with topic filter `event.type == "com.dapr.event.sent"`.
- **JSON serialization** uses `JsonNamingPolicy.CamelCase` on both ends; `SampleMessage` in the `models` library is the shared wire schema.

### Deployment View — KinD

```mermaid
flowchart TB
    subgraph host["Host (Docker)"]
        cpk["cloud-provider-kind<br/>(LoadBalancer daemon)"]
        subgraph cluster["KinD cluster: dapr-kafka (kindest/node:v1.35.0)"]
            subgraph ns_dapr["Namespace: dapr-system"]
                daprCP["Dapr control plane<br/>operator · placement · sentry · sidecar-injector"]
            end
            subgraph ns_kafka["Namespace: kafka"]
                kafkaSts["Kafka StatefulSet<br/>bitnamilegacy/kafka:4.0.0-debian-12-r10<br/>(Bitnami chart 32.4.3)"]
            end
            subgraph ns_app["Namespace: dapr-app"]
                subgraph podP["Pod: producer"]
                    p_app[".NET 10 producer"]
                    p_side["daprd sidecar<br/>(injected)"]
                end
                subgraph podC["Pod: consumer"]
                    c_app["ASP.NET Core consumer<br/>:6000"]
                    c_side["daprd sidecar<br/>(injected)"]
                end
                lb["Service: consumer<br/>LoadBalancer :80 → :6000"]
            end
        end
    end
    daprCP -.->|webhook injects sidecar| podP
    daprCP -.->|webhook injects sidecar| podC
    p_app -->|PublishEventAsync| p_side
    p_side -->|produce sampletopic| kafkaSts
    kafkaSts -->|consume sampletopic| c_side
    c_side -->|POST /sampletopic| c_app
    cpk -.->|allocates IP on kind network| lb
    lb -.->|"external traffic (optional)"| c_app
```

- **cloud-provider-kind** runs host-side (not in the cluster) and allocates LoadBalancer IPs on the `kind` Docker network — replaces MetalLB in the portfolio.
- **Sidecar injection**: Dapr's `sidecar-injector` mutating webhook adds the `daprd` container to any pod annotated `dapr.io/enabled: "true"`. Both producer and consumer pods end up 2-container.
- **Kafka** is in a separate namespace via the Bitnami chart. Note: the K8s path is still on `bitnamilegacy/kafka:4.0.0-debian-12-r10` (a frozen community archive — migration to `apache/kafka` or Strimzi is tracked in CLAUDE.md's Upgrade Backlog). The Docker Compose paths have already migrated to `apache/kafka:4.0.2`.
- **Consumer Service** is `type: LoadBalancer` so the `e2e/e2e-test.sh` script can curl it from the host — otherwise the demo uses Dapr pub/sub, not HTTP ingress.

### Source code layout

```text
producer/           Console app — publishes SampleMessage every 10s
  Program.cs        DaprClient.PublishEventAsync("sampletopic", "sampletopic", ...)
  deploy/           Dapr component YAML for local standalone mode

consumer/           ASP.NET Core web app — listens on :6000 (AppBindUrl constant)
  Program.cs        Host builder, binds http://*:6000
  Startup.cs        AddDaprClient + UseCloudEvents + MapPost("sampletopic")
                    Topic filter: event.type == "com.dapr.event.sent"

models/             Shared library (net10.0)
  SampleMessage.cs  CorrelationId, MessageId, Message, CreationDate, Sentiment, PreviousAppTimestamp

tests/              TUnit test projects (unit + integration)
e2e/                KinD + Docker Compose end-to-end shell scripts
```

Diagram sources live inline in this README — they are authored in Mermaid and parsed on every push by `make mermaid-lint` (pinned `minlag/mermaid-cli` Docker image) as part of `make static-check`.

## Running Locally

### Install Dapr in standalone mode

```bash
dapr init
```

See [Dapr standalone mode setup](https://docs.dapr.io/getting-started/install-dapr-selfhost/) for details.

### Start Kafka

Single-broker KRaft, plaintext, auto-creates topics — the default for the demo:

```bash
docker compose -f ./docker-compose-kafka.yaml up -d
```

A 3-node KRaft cluster (plaintext, no SASL+SSL) is also available via `docker-compose.yaml` — useful for broker-topology testing. Requires Dapr component changes (`brokers: "localhost:9094,localhost:9095,localhost:9096"`):

```bash
make local-kafka-run   # start
make local-kafka-stop  # stop
```

### Run consumer and producer

```bash
# Terminal 1
cd consumer && dapr run --app-id consumer --app-port 6000 --resources-path ../components -- dotnet run

# Terminal 2
cd producer && dapr run --app-id producer --resources-path ../components -- dotnet run
```

Or via Makefile shortcuts (equivalent):

```bash
make dapr-run-consumer
make dapr-run-producer
```

### Stop Kafka

```bash
docker compose -f ./docker-compose-kafka.yaml down
```

## Build & Package

Multi-arch images (`linux/amd64`, `linux/arm64`) are built by the `docker` CI job on tag pushes and published to GHCR as `ghcr.io/andriykalashnykov/dapr-kafka-csharp/{producer,consumer}:<semver>`. Both images are digest-pinned in the Dockerfile (`mcr.microsoft.com/dotnet/{aspnet,sdk}:10.0@sha256:…`) for reproducibility. Local builds:

```bash
make image-build          # builds producer and consumer images via Buildx (tagged with current git tag)
make docker-smoke-test    # boot each image and grep for the boot marker (mirrors CI Gate 3)
```

## Kubernetes Deployment

Uses KinD (`kindest/node`) with [cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind) for `ServiceType: LoadBalancer`. cloud-provider-kind runs host-side and allocates IPs from the `kind` Docker network; no in-cluster MetalLB.

### One-command deploy

```bash
make kind-up       # create KinD cluster + start cloud-provider-kind + deploy Dapr + Kafka + workloads
make k8s-test      # verify pods healthy and messages flowing end-to-end
make kind-down     # stop cloud-provider-kind and delete the cluster
```

`make kind-up` is an alias for `kind-deploy`; `make kind-down` aliases `kind-destroy`.

### Step-by-step (granular)

```bash
make kind-create          # create KinD cluster (image pinned via KIND_NODE_IMAGE, Renovate-tracked)
make kind-setup           # start cloud-provider-kind LoadBalancer daemon (requires sudo)
make k8s-dapr-deploy      # install Dapr via Helm
make k8s-kafka-deploy     # install Kafka (Bitnami chart 32.4.3, Kafka 4.0, SASL)
make k8s-workload-deploy  # build images, kind load docker-image, deploy apps
make k8s-test             # verify message flow
```

Check logs:

```bash
kubectl logs -f -l app=producer -c producer -n dapr-app
kubectl logs -f -l app=consumer -c consumer -n dapr-app
```

### Cleanup

```bash
make k8s-undeploy      # undeploy workloads + Kafka + Dapr + cluster
make kind-down         # just tear down the cluster
```

## Available Make Targets

Run `make help` for the generated list.

### Build & Test

| Target | Description |
|--------|-------------|
| `make build` | Build the solution |
| `make test` | Unit tests (in-process, seconds) |
| `make integration-test` | Integration tests against Testcontainers (seconds–tens of seconds, requires Docker) |
| `make e2e` | End-to-end tests — deploys to KinD via `kind-up`, asserts message flow (minutes) |
| `make e2e-compose` | End-to-end tests via Docker Compose (lighter alternative) |
| `make clean` | Remove build artifacts |
| `make format` | Auto-fix code formatting |

### Run

| Target | Description |
|--------|-------------|
| `make dapr-run-producer` | Run producer with Dapr sidecar |
| `make dapr-run-consumer` | Run consumer with Dapr sidecar (app-port 6000) |
| `make image-build` | Build Docker images (tagged with current git tag) |
| `make docker-smoke-test` | Boot each image and grep for the boot marker (mirrors CI Gate 3) |
| `make local-kafka-run` | Start 3-node plaintext KRaft Kafka cluster (advanced) |
| `make local-kafka-stop` | Stop the 3-node Kafka cluster |

### Static checks

| Target | Description |
|--------|-------------|
| `make lint` | Format check + warnings-as-errors + hadolint |
| `make static-check` | Composite: `lint + vulncheck + secrets + trivy-fs + trivy-config + mermaid-lint + deps-prune-check` |
| `make vulncheck` | `dotnet list package --vulnerable` |
| `make secrets` | gitleaks scan |
| `make trivy-fs` | Trivy filesystem scan (CRITICAL/HIGH) |
| `make trivy-config` | Trivy scan on `k8s/` manifests |
| `make mermaid-lint` | Parse every ```mermaid block in markdown files (pinned `minlag/mermaid-cli`) |
| `make deps-prune-check` | Detect unused transitive NuGet packages (NU1510) |

### CI

| Target | Description |
|--------|-------------|
| `make ci` | Full local CI pipeline (static-check + test + integration-test + build) |
| `make ci-run` | Run GitHub Actions workflow locally via [act](https://github.com/nektos/act) |

### Kubernetes

| Target | Description |
|--------|-------------|
| `make kind-up` | Alias for `kind-deploy` — full KinD stack (cluster + cloud-provider-kind + Dapr + Kafka + workloads) |
| `make kind-down` | Alias for `kind-destroy` — stop cloud-provider-kind and delete the cluster |
| `make k8s-deploy` | Alias for `kind-deploy` (granular) |
| `make k8s-undeploy` | Undeploy workloads + Kafka + Dapr + cluster |
| `make k8s-test` | Verify K8s deployment (pods running, messages flowing) |
| `make deps-k8s` | Check Kubernetes tools (kind, cloud-provider-kind, kubectl, helm, dapr) |
| `make kind-create` / `make kind-destroy` | Create/delete KinD cluster (granular) |
| `make kind-setup` / `make kind-lb-stop` | Start/stop cloud-provider-kind LoadBalancer daemon (granular) |
| `make kind-list` | List KinD clusters |
| `make k8s-dapr-deploy` / `make k8s-dapr-undeploy` | Dapr Helm install/uninstall |
| `make k8s-kafka-deploy` / `make k8s-kafka-undeploy` | Bitnami Kafka chart install/uninstall |
| `make k8s-image-load` | Build images and `kind load docker-image` into the cluster |
| `make k8s-workload-deploy` / `make k8s-workload-undeploy` | Producer + consumer lifecycle |

### Utilities

| Target | Description |
|--------|-------------|
| `make deps` | Install CLI toolchain via mise |
| `make deps-mise` | Install mise (no root required) |
| `make update` | Show outdated NuGet packages |
| `make release` | Create and push a new semver tag |
| `make version` | Print current version tag |
| `make renovate-validate` | Validate Renovate configuration locally |

## CI/CD

GitHub Actions runs on push to `main`, tag pushes (`v*`), and pull requests. The `ci-pass` gate aggregates all upstream jobs into a single required status check for branch protection.

| Job | Triggers | Steps |
|-----|----------|-------|
| **static-check** | push, PR, tags | Format check, warnings-as-errors, hadolint |
| **build** | after static-check | Build the solution |
| **test** | after static-check | Run unit tests, upload results artifact |
| **integration-test** | after static-check | Run integration tests (`Category=Integration`), upload results |
| **e2e** | after build + test | End-to-end tests (when scaffolded) |
| **docker** | tag push (`v*`) | Pre-push hardening (Trivy image scan + smoke test), multi-arch build, push to GHCR, cosign keyless signing |
| **ci-pass** | always | Aggregate pass/fail gate |

### Pre-push image hardening

The `docker` job runs the following gates **before** any image is pushed to GHCR. Any failure blocks the release.

| # | Gate | Catches | Tool |
|---|------|---------|------|
| 1 | Build local single-arch image | Build regressions on the runner architecture | `docker/build-push-action` with `load: true` |
| 2 | **Trivy image scan** (CRITICAL/HIGH blocking) | CVEs in the base image, OS packages, build layers | `aquasecurity/trivy-action` with `image-ref:` |
| 3 | **Smoke test** | Image boots correctly on its own (boot-marker grep; NOT a health-curl, since both apps depend on the Dapr sidecar) | `docker run` + `docker logs` |
| 4 | Multi-arch build + push | Publishes for both `linux/amd64` and `linux/arm64` | `docker/build-push-action` |
| 5 | **Cosign keyless OIDC signing** | Sigstore signature on the manifest digest | `sigstore/cosign-installer` + `cosign sign --yes ...@<digest>` |

Buildkit in-manifest attestations (`provenance` + `sbom`) are disabled (Pattern A) so the image index stays free of `unknown/unknown` platform entries, which lets the GHCR Packages UI render the "OS / Arch" tab for the multi-arch manifest. Cosign keyless signing still provides the Sigstore signature for supply-chain verification.

Verify a published image's signature:

```bash
cosign verify ghcr.io/andriykalashnykov/dapr-kafka-csharp/consumer:<tag> \
  --certificate-identity-regexp 'https://github\.com/AndriyKalashnykov/dapr-kafka-csharp/.+' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Local parity with Gate 3 via `make docker-smoke-test`.

A weekly **cleanup** workflow (`cleanup-runs.yml`) prunes runs older than 7 days (minimum 5 retained) and stale pull-request caches.

### Required Secrets and Variables

| Name | Type | Used by | How to obtain |
|------|------|---------|---------------|
| `GITHUB_TOKEN` | Secret | `docker` (GHCR push) | Built-in — no configuration required |

No external secrets or `vars.*` are required.

[Renovate](https://docs.renovatebot.com/) keeps dependencies up to date with platform automerge enabled. Every version pin (`.mise.toml`, `Makefile`, NuGet `*.csproj`, Dockerfiles, docker-compose, GitHub Actions) is tracked.

## Contributing

Contributions welcome — open a PR.

## References

- [Practical Microservices with Dapr and .NET (Packt)](https://github.com/PacktPublishing/Practical-Microservices-with-Dapr-and-.NET/tree/main)
- [ACA DAPR Demo](https://github.com/nissbran/aca-dapr-demo)
- [Apache Kafka with Dapr Bindings in .NET](https://www.c-sharpcorner.com/article/apache-kafka-with-dapr-bindings-in-net/)

## License

MIT — see [LICENSE](./LICENSE).
