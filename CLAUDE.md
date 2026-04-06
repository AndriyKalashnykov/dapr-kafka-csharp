# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dapr PubSub demo with Apache Kafka in C# (.NET 10). A **producer** console app publishes `SampleMessage` events to a Kafka topic via Dapr, and a **consumer** ASP.NET Core web app subscribes and processes them. Both share a **models** library.

## Build Commands

```bash
make build          # Build the solution
make clean          # Clean solution and remove bin/ and obj/ directories
make image-build    # Build Docker images for producer and consumer
make update         # Update outdated NuGet packages across all projects
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

# 2. Run consumer (in one terminal)
cd consumer && dapr run --app-id consumer --app-port 6000 -- dotnet run

# 3. Run producer (in another terminal)
cd producer && dapr run --app-id producer --resources-path ./deploy -- dotnet run

# Or use Makefile shortcuts (without Dapr sidecar):
make dapr-run-consumer    # Run consumer
make dapr-run-producer    # Run producer
```

There is also a 3-node KRaft Kafka cluster via `docker-compose.yaml` (SASL+SSL, Bitnami images, Kafka 4.0):
```bash
make local-kafka-run   # Start
make local-kafka-stop  # Stop
```

### Kafka Infrastructure

Both Compose files use KRaft mode (no Zookeeper):
- **`docker-compose-kafka.yaml`** — single-broker, plaintext, auto-creates topics. For local dev.
- **`docker-compose.yaml`** — 3-node KRaft cluster with SASL+SSL. Image pinned via `KAFKA_IMAGE` in `.env`.
- **K8s Helm** — `scripts/kafka.sh` installs `bitnami/kafka` chart (v32.4.4, Kafka 4.0) with SASL, KRaft, and provisioned topics.

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
- Dapr component config: `producer/deploy/kafka-pubsub.yaml` (local) / `k8s/kafka-pubsub.yaml` (Kubernetes)
- Consumer uses `Startup.cs` pattern (not minimal API), with `UseCloudEvents()` middleware to unwrap CloudEvents payloads
- JSON serialization uses camelCase naming policy (`JsonNamingPolicy.CamelCase`)

## Kubernetes Deployment

```bash
# Full stack deploy (one command)
make k8s-deploy           # Minikube + Dapr + Kafka + workloads

# Or step-by-step
make minikube-start       # Start Minikube (profile: dapr-dotnet)
make k8s-dapr-deploy      # Install Dapr via Helm
make k8s-kafka-deploy     # Install Kafka via Bitnami Helm chart (Kafka 4.0)
make k8s-image-load       # Build + load images into Minikube
make k8s-workload-deploy  # Deploy namespace, Dapr component, producer, consumer

# Verify
make k8s-test             # Check pods running, messages flowing end-to-end

# Teardown
make k8s-undeploy         # Full undeploy (workloads + Kafka + Dapr)
make minikube-delete      # Delete Minikube cluster
```

K8s manifests are in `k8s/` (namespace: `dapr-app`). The `deps-k8s` target checks for minikube, kubectl, helm, and dapr CLI.

## Testing

```bash
make test           # Run all tests (dotnet test in Release config)
make ci             # Full local CI pipeline: lint + build + test
make ci-run         # Run GitHub Actions workflow locally via act
```

## Formatting

```bash
make lint           # Check formatting (dotnet format --verify-no-changes) + warnings-as-errors + hadolint Dockerfiles
make format         # Auto-fix code formatting (dotnet format)
```

## Key Details

- .NET SDK version pinned in `global.json` (10.0.201, `rollForward: latestMajor`, `allowPrerelease: true`)
- All projects target `net10.0`
- Each project has its own `nuget.config` pointing to NuGet v3 feed
- Docker images: both producer and consumer use `dotnet/aspnet:10.0` base (Dapr.AspNetCore requires ASP.NET runtime)
- `Directory.Build.props` enforces `TreatWarningsAsErrors` and `RestorePackagesWithLockFile` across all projects
- Renovate bot manages dependency updates

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs three parallel jobs on push/PR to main and tag pushes: `lint` (format check + warnings-as-errors + hadolint) gates `build` and `test` which run in parallel. On tag pushes (`v*`), a `docker` job builds multi-arch images (`linux/amd64`, `linux/arm64`) and pushes to GHCR (`ghcr.io`). Uses `GITHUB_TOKEN` with `packages: write` permission.

A weekly cleanup workflow (`.github/workflows/cleanup-runs.yml`) prunes old workflow runs older than 7 days, keeping a minimum of 5.

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.yml` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
