# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dapr PubSub demo with Apache Kafka in C# (.NET 8). A **producer** console app publishes `SampleMessage` events to a Kafka topic via Dapr, and a **consumer** ASP.NET Core web app subscribes and processes them. Both share a **models** library.

## Build Commands

```bash
make build          # Clean and build all three projects
make clean          # Remove bin/ and obj/ directories
make image-build    # Build Docker images for producer and consumer
make help           # List all available Makefile targets
```

Individual project builds:
```bash
cd consumer && dotnet build consumer.csproj
cd producer && dotnet build producer.csproj
cd models && dotnet build models.csproj
```

## Running Locally

```bash
# 1. Start Kafka (simple single-broker with Zookeeper)
docker-compose -f ./docker-compose-kafka.yaml up -d

# 2. Run consumer (in one terminal)
cd consumer && dapr run --app-id consumer --app-port 6000 -- dotnet run

# 3. Run producer (in another terminal)
cd producer && dapr run --app-id producer --resources-path ./deploy -- dotnet run

# Or use Makefile shortcuts (without Dapr sidecar):
make runc    # Run consumer
make runp    # Run producer
```

There is also a 3-node KRaft Kafka cluster via `docker-compose.yaml` (SASL+SSL, Bitnami images):
```bash
make local-kafka-run   # Start
make local-kafka-stop  # Stop
```

## Architecture

```
producer/           Console app (Exe) - publishes SampleMessage every 10s
  Program.cs        DaprClient → PublishEventAsync("sampletopic", "sampletopic", ...)
  deploy/           Dapr component YAML for local standalone mode

consumer/           ASP.NET Core Web app - listens on port 6000
  Program.cs        Host builder, binds to http://*:6000
  Startup.cs        Configures Dapr, CloudEvents, MapPost("sampletopic") subscription
                    Topic filter: event.type == "com.dapr.event.sent"

models/             Shared library (netstandard2.1, no dependencies)
  SampleMessage.cs  CorrelationId, MessageId, Message, CreationDate, Sentiment, PreviousAppTimestamp
```

- PubSub component name and topic name are both `"sampletopic"`
- Dapr component config: `producer/deploy/kafka-pubsub.yaml` (local) / `k8s/kafka-pubsub.yaml` (Kubernetes)
- No root-level `.sln` file; each project is built individually

## Kubernetes Deployment

```bash
make minikube-start       # Start Minikube (profile: dapr)
make k8s-dapr-deploy      # Install Dapr via Helm
make k8s-kafka-deploy     # Install Kafka via Bitnami Helm chart
make k8s-image-load       # Build + load images into Minikube
make k8s-workload-deploy  # Deploy namespace, Dapr component, producer, consumer
make k8s-workload-undeploy
make k8s-kafka-undeploy
make k8s-dapr-undeploy
```

K8s manifests are in `k8s/` (namespace: `dapr-app`).

## Dependencies

| Package | Version | Used By |
|---------|---------|---------|
| Dapr.Client | 1.17.0 | producer, consumer |
| Dapr.AspNetCore | 1.16.1 | producer, consumer |

.NET SDK version is pinned in `global.json` (8.0.x with `rollForward: latestMajor`).

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs `make build image-build` on push/PR to main. No tests in CI.

## NuGet Configuration

All projects use `nuget.config` files pointing to the NuGet v3 feed. Package upgrades: `make upgrade`.
