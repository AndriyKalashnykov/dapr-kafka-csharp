[![CI](https://github.com/AndriyKalashnykov/dapr-kafka-csharp/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/dapr-kafka-csharp/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/dapr-kafka-csharp.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/dapr-kafka-csharp/)
[![.NET](https://img.shields.io/badge/.NET-10.0-512BD4?logo=dotnet)](https://dotnet.microsoft.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/dapr-kafka-csharp)

# Dapr Kafka PubSub in C#

Dapr PubSub demo with Apache Kafka in C# (.NET 10). A **producer** console app publishes `SampleMessage` events to a Kafka topic via Dapr, and a **consumer** ASP.NET Core web app subscribes and processes them. Both share a **models** library.

## Quick Start

```bash
make deps                    # verify required tools
make build                   # build the solution
docker compose -f ./docker-compose-kafka.yaml up -d   # start Kafka
make dapr-run-consumer       # run consumer (terminal 1)
make dapr-run-producer       # run producer (terminal 2)
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Git](https://git-scm.com/) | 2.x+ | Version control |
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+ | Build orchestration |
| [.NET SDK](https://dotnet.microsoft.com/download) | 10.0+ | Build and run C# projects |
| [Docker](https://www.docker.com/) | latest | Run Kafka, build container images |
| [Dapr CLI](https://docs.dapr.io/getting-started/install-dapr-cli/) | latest | Run Dapr sidecars locally |
| [Minikube](https://minikube.sigs.k8s.io/) | latest | Local Kubernetes cluster (optional) |
| [Helm](https://helm.sh/) | latest | Deploy Dapr/Kafka to Kubernetes (optional) |

Install required dependencies:

```bash
make deps
```

## Available Make Targets

Run `make help` to see all available targets.

### Build & Run

| Target | Description |
|--------|-------------|
| `make build` | Build the solution |
| `make clean` | Remove build artifacts |
| `make test` | Run tests |
| `make lint` | Check code formatting and lint Dockerfiles |
| `make format` | Auto-fix code formatting |
| `make dapr-run-producer` | Run producer |
| `make dapr-run-consumer` | Run consumer |

### Docker & Kafka

| Target | Description |
|--------|-------------|
| `make image-build` | Build Docker images |
| `make local-kafka-run` | Run a local Kafka instance |
| `make local-kafka-stop` | Stop a local Kafka instance |

### CI

| Target | Description |
|--------|-------------|
| `make ci` | Run full local CI pipeline |
| `make ci-run` | Run GitHub Actions workflow locally via [act](https://github.com/nektos/act) |
| `make deps-act` | Install act for local CI |

### Kubernetes

| Target | Description |
|--------|-------------|
| `make k8s-deploy` | Full K8s deploy (Dapr + Kafka + workloads) |
| `make k8s-undeploy` | Full K8s undeploy (workloads + Kafka + Dapr) |
| `make k8s-test` | Verify K8s deployment (pods running, messages flowing) |
| `make deps-k8s` | Check Kubernetes tools (minikube, kubectl, helm, dapr) |
| `make minikube-start` | Start Minikube |
| `make minikube-stop` | Stop Minikube |
| `make minikube-delete` | Delete Minikube |
| `make minikube-list` | List Minikube profiles |
| `make k8s-dapr-deploy` | Deploy Dapr to Kubernetes |
| `make k8s-dapr-undeploy` | Undeploy Dapr from Kubernetes |
| `make k8s-kafka-deploy` | Deploy Kafka to Kubernetes |
| `make k8s-kafka-undeploy` | Undeploy Kafka from Kubernetes |
| `make k8s-image-load` | Build and load images into Minikube |
| `make k8s-workload-deploy` | Deploy producer and consumer to Kubernetes |
| `make k8s-workload-undeploy` | Undeploy workloads from Kubernetes |

### Utilities

| Target | Description |
|--------|-------------|
| `make deps` | Check required tools |
| `make deps-hadolint` | Install hadolint for Dockerfile linting |
| `make update` | Update outdated NuGet packages |
| `make release` | Create and push a new tag |
| `make version` | Print current version (tag) |
| `make renovate-bootstrap` | Install nvm and npm for Renovate |
| `make renovate-validate` | Validate Renovate configuration |

## Running Locally

### Install Dapr in standalone mode

[Install Dapr in standalone mode](https://github.com/dapr/docs/blob/master/getting-started/environment-setup.md#installing-dapr-in-standalone-mode):

```bash
dapr init
```

### Run Kafka Docker Container Locally

Run Kafka locally (single-broker KRaft, no Zookeeper):

```bash
docker compose -f ./docker-compose-kafka.yaml up -d
```

There is also a 3-node KRaft Kafka cluster via `docker-compose.yaml` (SASL+SSL, Bitnami Kafka 4.0):

```bash
make local-kafka-run   # Start
make local-kafka-stop  # Stop
```

### Run Consumer app

```bash
cd consumer
dapr run --app-id consumer --app-port 6000 -- dotnet run
```

### Run Producer app

```bash
cd producer
dapr run --app-id producer --resources-path ./deploy -- dotnet run
```

### Uninstall Kafka

```bash
docker compose -f ./docker-compose-kafka.yaml down
```

## Run in Kubernetes Cluster

### One-command deploy

```bash
make k8s-deploy    # Starts Minikube, installs Dapr + Kafka, builds and deploys workloads
make k8s-test      # Verifies pods running and messages flowing end-to-end
```

### Step-by-step deploy

```bash
make minikube-start       # Start Minikube (profile: dapr-dotnet)
make k8s-dapr-deploy      # Install Dapr via Helm
make k8s-kafka-deploy     # Install Kafka (Bitnami chart, Kafka 4.0, SASL)
make k8s-workload-deploy  # Build images, load into Minikube, deploy apps
make k8s-test             # Verify everything works
```

Check logs:

```bash
kubectl logs -f -l app=producer -c producer -n dapr-app
kubectl logs -f -l app=consumer -c consumer -n dapr-app
```

### Cleanup

```bash
make k8s-undeploy      # Undeploy workloads + Kafka + Dapr
make minikube-delete   # Delete Minikube cluster
```

## Build and Push Docker Images

1. Build Docker images:

```bash
make image-build
```

2. Push Docker images to your registry:

```bash
docker push [docker_registry]/consumer:latest
docker push [docker_registry]/producer:latest
```

3. Update image names in [k8s/consumer.yaml](k8s/consumer.yaml) and [k8s/producer.yaml](k8s/producer.yaml).

## CI/CD

GitHub Actions runs on every push to `main`, tags `v*`, and pull requests.

| Job | Triggers | Steps |
|-----|----------|-------|
| **lint** | push, PR, tags | Format check, compiler warnings-as-errors, hadolint |
| **build** | after lint passes | Build the solution |
| **test** | after lint passes | Run tests |
| **docker** | tag push (`v*`) | QEMU, Buildx, Login, Build & Push multi-arch images |

A weekly **cleanup** workflow prunes old workflow runs (retains 7 days, minimum 5 runs).

Docker images are pushed to GHCR (`ghcr.io`) on tag pushes with semver tags (`v1.2.3` → `1.2.3`, `1.2`, `1`). Uses `GITHUB_TOKEN` with `packages: write` permission (no extra secrets needed).

[Renovate](https://docs.renovatebot.com/) keeps dependencies up to date with platform automerge enabled.

## References

- [Practical Microservices with Dapr and .NET, published by Packt](https://github.com/PacktPublishing/Practical-Microservices-with-Dapr-and-.NET/tree/main)
- [ACA DAPR Demo](https://github.com/nissbran/aca-dapr-demo)
- [Apache Kafka with Dapr Bindings in .NET](https://www.c-sharpcorner.com/article/apache-kafka-with-dapr-bindings-in-net/)
