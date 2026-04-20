.DEFAULT_GOAL := help
SHELL          := /bin/bash

APP_NAME       := dapr-kafka-csharp
CURRENTTAG     := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")

# Ensure mise shims + user-local bin are on PATH so installed tools are found in recipes.
# mise shims FIRST so mise-managed tool versions (.mise.toml) authoritatively beat any
# older manually-installed binaries in ~/.local/bin.
export PATH := $(HOME)/.local/share/mise/shims:$(HOME)/.local/bin:$(PATH)

# === Project Paths ===
SOLUTION       := dapr-kafka-csharp.slnx
PRODUCER_IMG   ?= andriykalashnykov/producer:$(CURRENTTAG)
CONSUMER_IMG   ?= andriykalashnykov/consumer:$(CURRENTTAG)

# === KinD cluster settings ===
KIND_CLUSTER_NAME := dapr-kafka

# renovate: datasource=docker depName=kindest/node
KIND_NODE_IMAGE := kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f

# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.12.0

# === Kafka / Dapr pinned versions (Renovate-tracked via inline comments). ===
# renovate: datasource=github-releases depName=dapr/dapr
DAPR_CHART_VERSION := 1.17.5

# renovate: datasource=helm depName=kafka registryUrl=https://charts.bitnami.com/bitnami
KAFKA_CHART_VERSION := 32.4.3

# renovate: datasource=docker depName=apache/kafka
KAFKA_IMAGE_VERSION := 4.0.2

# Legacy Bitnami image tag — still consumed by scripts/kafka.sh (K8s Helm chart path).
# Bitnami moved to a paid registry in 2025; bitnamilegacy/* is a frozen community archive.
# Deferred migration: switch K8s path off Bitnami chart to a maintained alternative (strimzi or Apache Kafka image via a custom chart).
BITNAMI_KAFKA_LEGACY_TAG := 4.0.0-debian-12-r10

export KAFKA_CHART_VERSION KAFKA_IMAGE_VERSION BITNAMI_KAFKA_LEGACY_TAG DAPR_CHART_VERSION

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-27s\033[0m - %s\n", $$1, $$2}'

#deps-mise: @ Install mise (no root required)
deps-mise:
	@command -v mise >/dev/null 2>&1 || { \
		echo "Installing mise..."; \
		curl -fsSL https://mise.run | sh; \
	}

#deps: @ Install required tools via mise (skips under `act` where setup-dotnet already provides .NET)
deps: deps-mise
	@command -v dotnet >/dev/null 2>&1 || { echo "Error: .NET SDK required. See https://dotnet.microsoft.com/download"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "Error: Docker required. See https://docs.docker.com/get-docker/"; exit 1; }
	@if [ -n "$$ACT" ]; then \
		echo "act detected — skipping 'mise install' (per-target tool install happens on demand); setup-dotnet provides .NET"; \
	else \
		mise install; \
		DOTNET_SDK_REQUIRED=$$(jq -r '.sdk.version' global.json 2>/dev/null || echo ""); \
		if [ -n "$$DOTNET_SDK_REQUIRED" ]; then \
			dotnet --list-sdks | grep -q "$$DOTNET_SDK_REQUIRED" || \
				echo "Warning: .NET SDK $$DOTNET_SDK_REQUIRED not installed (global.json rollForward may cover this)"; \
		fi; \
	fi

#deps-k8s: @ Check Kubernetes tools (kind, cloud-provider-kind, kubectl, helm, dapr)
deps-k8s: deps
	@command -v kind >/dev/null 2>&1 || { echo "Error: kind required (installed via mise)"; exit 1; }
	@command -v cloud-provider-kind >/dev/null 2>&1 || { echo "Error: cloud-provider-kind required (installed via mise)"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl required (installed via mise)"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "Error: Helm required (installed via mise)"; exit 1; }
	@command -v dapr >/dev/null 2>&1 || { echo "Error: Dapr CLI required (installed via mise)"; exit 1; }

#clean: @ Remove build artifacts
clean:
	@dotnet clean "$(SOLUTION)" -v q --nologo
	@rm -rf ./consumer/bin/ ./consumer/obj/
	@rm -rf ./models/bin/ ./models/obj/
	@rm -rf ./producer/bin/ ./producer/obj/

#build: @ Build the solution
build: deps
	@dotnet build "$(SOLUTION)" --nologo -v q

#test: @ Run unit tests (fast, in-process)
test: deps
	@dotnet test --solution "$(SOLUTION)" -c Release

#integration-test: @ Run integration tests (projects ending in .IntegrationTests; Testcontainers where applicable)
integration-test: deps
	@set -e; for proj in $$(find tests -name '*.IntegrationTests.csproj'); do \
		echo "=== $$proj ==="; \
		dotnet run --project "$$proj" -c Release; \
	done

#e2e: @ Run end-to-end tests (KinD deploy + curl assertions through LoadBalancer)
e2e: k8s-deploy
	@if [ -x e2e/e2e-test.sh ]; then ./e2e/e2e-test.sh; else \
		echo "e2e/e2e-test.sh missing — run /test-coverage-analysis to scaffold"; exit 1; \
	fi

#e2e-compose: @ Run end-to-end tests via Docker Compose (lighter alternative to k8s e2e)
e2e-compose:
	@docker compose -f docker-compose-kafka.yaml up -d --wait
	@if [ -x e2e/e2e-compose-test.sh ]; then \
		./e2e/e2e-compose-test.sh; RC=$$?; docker compose -f docker-compose-kafka.yaml down; exit $$RC; \
	else \
		docker compose -f docker-compose-kafka.yaml down; \
		echo "e2e/e2e-compose-test.sh missing — run /test-coverage-analysis to scaffold"; exit 1; \
	fi

#vulncheck: @ Audit NuGet packages for known CVEs
vulncheck: deps
	@set -e; \
	for proj in consumer models producer; do \
		echo "--- $$proj ---"; \
		dotnet list $$proj/$$proj.csproj package --vulnerable --include-transitive 2>&1 | tee /tmp/$$proj-vuln.log; \
		if grep -qE "has the following vulnerable" /tmp/$$proj-vuln.log; then \
			echo "Vulnerable packages found in $$proj"; exit 1; \
		fi; \
	done

#secrets: @ Scan repo for leaked secrets (gitleaks)
secrets: deps
	@gitleaks detect --source . --redact --no-banner

#trivy-fs: @ Trivy filesystem scan (CRITICAL/HIGH blocking)
trivy-fs: deps
	@trivy fs --severity CRITICAL,HIGH --exit-code 1 --ignore-unfixed .

#trivy-config: @ Trivy config scan on Kubernetes manifests
trivy-config: deps
	@trivy config --severity CRITICAL,HIGH --exit-code 1 k8s/

#mermaid-lint: @ Parse every ```mermaid block with pinned minlag/mermaid-cli (same engine github.com uses)
mermaid-lint:
	@set -e; \
	files=$$(grep -rln --include="*.md" -E '^[[:space:]]*```mermaid$$' . 2>/dev/null || true); \
	if [ -z "$$files" ]; then echo "No mermaid blocks found"; exit 0; fi; \
	for f in $$files; do \
		echo "=== linting $$f ==="; \
		docker run --rm -v "$(CURDIR):/data" -w /data \
			minlag/mermaid-cli:$(MERMAID_CLI_VERSION) \
			-i "$$f" -o "/tmp/$$(basename $$f).rendered.md" \
			>/dev/null 2>&1 || { echo "FAIL: broken mermaid in $$f"; exit 1; }; \
	done; \
	echo "mermaid-lint passed"

#deps-prune-check: @ Detect unused transitive NuGet packages (NU1510)
deps-prune-check: deps
	@set -e; out=$$(dotnet build "$(SOLUTION)" -c Release --nologo -v q 2>&1 | grep "NU1510" || true); \
		if [ -n "$$out" ]; then echo "$$out"; echo "Unused top-level dependencies detected"; exit 1; fi

#lint: @ Check formatting, warnings-as-errors, and Dockerfile lint (hadolint via native CLI or Docker fallback)
lint: deps
	@dotnet format "$(SOLUTION)" --verify-no-changes
	@dotnet build "$(SOLUTION)" -warnaserror --nologo -v q
	@if command -v hadolint >/dev/null 2>&1; then \
		hadolint consumer/Dockerfile; \
		hadolint producer/Dockerfile; \
	else \
		docker run --rm -v "$(CURDIR):/workspace" -w /workspace hadolint/hadolint hadolint consumer/Dockerfile; \
		docker run --rm -v "$(CURDIR):/workspace" -w /workspace hadolint/hadolint hadolint producer/Dockerfile; \
	fi

#static-check: @ Composite quality gate (lint + vulncheck + secrets + trivy-fs + trivy-config + mermaid-lint + deps-prune-check)
static-check: lint vulncheck secrets trivy-fs trivy-config mermaid-lint deps-prune-check

#format: @ Auto-fix code formatting
format: deps
	@dotnet format "$(SOLUTION)"

#ci: @ Run full local CI pipeline (static-check + test + integration-test + build)
ci: deps static-check test integration-test build
	@echo "Local CI pipeline passed."

#ci-run: @ Run GitHub Actions workflow locally via act (pass GH_ACCESS_TOKEN to avoid mise/aqua GitHub rate-limit inside the container)
ci-run: deps
	@if [ -z "$$GH_ACCESS_TOKEN" ]; then \
		echo "Warning: GH_ACCESS_TOKEN not set — mise tool resolution inside act will hit the 60/hour unauthenticated rate limit."; \
		act push --container-architecture linux/amd64 \
			--artifact-server-path /tmp/act-artifacts \
			--var ACT=true \
			--concurrent-jobs 1; \
	else \
		act push --container-architecture linux/amd64 \
			--artifact-server-path /tmp/act-artifacts \
			--var ACT=true \
			--concurrent-jobs 1 \
			--secret GITHUB_TOKEN="$$GH_ACCESS_TOKEN"; \
	fi

#release: @ Create and push a new tag
release: deps
	@bash -c 'read -p "New tag (current: $(CURRENTTAG)): " newtag && \
		echo "$$newtag" | grep -qE "^v[0-9]+\.[0-9]+\.[0-9]+$$" || { echo "Error: Tag must match vN.N.N"; exit 1; } && \
		echo -n "Create and push $$newtag? [y/N] " && read ans && [ "$${ans:-N}" = y ] && \
		echo $$newtag > ./version.txt && \
		git add -A && \
		git diff --cached --quiet || git commit -s -m "Cut $$newtag release" && \
		git tag $$newtag && \
		git push origin $$newtag && \
		git push && \
		echo "Done."'

#version: @ Print current version(tag)
version:
	@echo $(CURRENTTAG)

#image-build: @ Build Docker images
image-build: build
	@docker buildx build --load -t $(PRODUCER_IMG) -f producer/Dockerfile .
	@docker buildx build --load -t $(CONSUMER_IMG) -f consumer/Dockerfile .

#docker-smoke-test: @ Boot each image locally and grep for the language-specific boot marker (mirrors CI Gate 3)
docker-smoke-test: image-build
	@set -e; \
	$(MAKE) --no-print-directory _smoke-one APP=producer IMG='$(PRODUCER_IMG)' MARKER='Publishing data:'; \
	$(MAKE) --no-print-directory _smoke-one APP=consumer IMG='$(CONSUMER_IMG)' MARKER='Now listening on:|Application started'

# Internal helper used by docker-smoke-test (not a public target).
_smoke-one:
	@echo "=== smoke $(APP) ($(IMG)) ==="
	@docker rm -f $(APP)-smoke >/dev/null 2>&1 || true
	@docker run -d --name=$(APP)-smoke "$(IMG)" >/dev/null
	@set -e; end=$$(( $$(date +%s) + 30 )); passed=0; \
	while [ $$(date +%s) -lt $$end ]; do \
		if docker logs $(APP)-smoke 2>&1 | grep -qE '$(MARKER)'; then \
			echo "PASS: $(APP) matched boot marker"; passed=1; break; \
		fi; sleep 2; \
	done; \
	docker rm -f $(APP)-smoke >/dev/null 2>&1 || true; \
	[ $$passed -eq 1 ] || { echo "FAIL: $(APP) did not hit boot marker within 30s"; exit 1; }

#local-kafka-run: @ Run a local 3-node plaintext KRaft Kafka cluster (advanced; requires Dapr component change)
local-kafka-run: local-kafka-stop
	@docker compose -f "docker-compose.yaml" up -d --wait

#local-kafka-stop: @ Stop the local Kafka cluster
local-kafka-stop:
	@docker compose -f "docker-compose.yaml" down

#dapr-run-producer: @ Run producer with Dapr sidecar (shared components/ dir)
dapr-run-producer: build
	@cd producer && dapr run --app-id producer --resources-path ../components -- dotnet run

#dapr-run-consumer: @ Run consumer with Dapr sidecar (app-port 6000, shared components/ dir)
dapr-run-consumer: build
	@cd consumer && dapr run --app-id consumer --app-port 6000 --resources-path ../components -- dotnet run

#update: @ Show outdated NuGet packages
update: deps
	@command -v dotnet-outdated >/dev/null 2>&1 || dotnet tool install --global dotnet-outdated-tool
	@dotnet outdated "$(SOLUTION)" -u:Prompt

#kind-create: @ Create KinD cluster
kind-create: deps-k8s
	@if kind get clusters 2>/dev/null | grep -qx "$(KIND_CLUSTER_NAME)"; then \
		echo "KinD cluster '$(KIND_CLUSTER_NAME)' already exists."; \
	else \
		kind create cluster --name "$(KIND_CLUSTER_NAME)" --image "$(KIND_NODE_IMAGE)" --wait 120s; \
	fi

#kind-setup: @ Start cloud-provider-kind load balancer (sudo-tolerant: skips with warning if sudo unavailable)
kind-setup: deps-k8s
	@if pgrep -f "cloud-provider-kind" >/dev/null 2>&1; then \
		echo "cloud-provider-kind already running"; \
	elif sudo -n true 2>/dev/null; then \
		echo "Starting cloud-provider-kind (passwordless sudo OK)..."; \
		sudo -b nohup cloud-provider-kind >/tmp/cloud-provider-kind.log 2>&1; \
		sleep 2; \
		pgrep -f "cloud-provider-kind" >/dev/null 2>&1 && \
			echo "cloud-provider-kind running; LoadBalancer IPs allocated from the kind Docker network." || \
			{ echo "Error: cloud-provider-kind failed to start — see /tmp/cloud-provider-kind.log"; exit 1; }; \
	else \
		echo "Warning: sudo requires a password; skipping cloud-provider-kind."; \
		echo "LoadBalancer services will stay in 'pending' state — pub/sub still works, but no external IPs."; \
		echo "To enable full LoadBalancer support, run 'sudo cloud-provider-kind &' manually, then 'make k8s-workload-deploy'."; \
	fi

#kind-lb-stop: @ Stop cloud-provider-kind daemon
kind-lb-stop:
	@sudo pkill -f "cloud-provider-kind" 2>/dev/null || true

#kind-destroy: @ Delete the KinD cluster (and stop cloud-provider-kind)
kind-destroy: kind-lb-stop
	@kind delete cluster --name "$(KIND_CLUSTER_NAME)" 2>/dev/null || true

#kind-list: @ List KinD clusters
kind-list: deps-k8s
	@kind get clusters

#k8s-dapr-deploy: @ Deploy Dapr control plane to k8s (dashboard uses ClusterIP; port-forward to access)
k8s-dapr-deploy: deps-k8s
	@helm repo add dapr https://dapr.github.io/helm-charts/
	@helm repo update
	@helm upgrade --install dapr dapr/dapr --set version=$(DAPR_CHART_VERSION) --namespace dapr-system --create-namespace --wait
	@helm upgrade --install dapr-dashboard dapr/dapr-dashboard --set version=$(DAPR_CHART_VERSION) --namespace dapr-system --wait
	@kubectl get pods --namespace dapr-system

#k8s-dapr-undeploy: @ Undeploy Dapr from k8s
k8s-dapr-undeploy: deps-k8s
	@helm uninstall dapr --namespace dapr-system && \
	helm uninstall dapr-dashboard --namespace dapr-system

#k8s-kafka-deploy: @ Deploy Kafka to k8s
k8s-kafka-deploy: deps-k8s
	@./scripts/kafka.sh install

#k8s-kafka-undeploy: @ Undeploy Kafka from k8s
k8s-kafka-undeploy: deps-k8s
	@./scripts/kafka.sh delete

#k8s-image-load: @ Build and load images into the KinD cluster
k8s-image-load: deps-k8s image-build
	@kind load docker-image "$(PRODUCER_IMG)" --name "$(KIND_CLUSTER_NAME)"
	@kind load docker-image "$(CONSUMER_IMG)" --name "$(KIND_CLUSTER_NAME)"

#k8s-workload-deploy: @ Deploy workloads to k8s (substitutes :$(CURRENTTAG) for the :v1.0.0 placeholder in manifests)
k8s-workload-deploy: k8s-image-load
	@kubectl apply -f ./k8s/ns.yaml
	@kubectl apply -f ./k8s/kafka-pubsub.yaml --namespace=dapr-app --wait=true
	@sed "s|:v1.0.0|:$(CURRENTTAG)|g" ./k8s/producer.yaml | kubectl apply --namespace=dapr-app --wait=true -f -
	@sed "s|:v1.0.0|:$(CURRENTTAG)|g" ./k8s/consumer.yaml | kubectl apply --namespace=dapr-app --wait=true -f -
	@kubectl wait --namespace dapr-app --for=condition=ready pod --selector=app=consumer --timeout=120s
	@kubectl wait --namespace dapr-app --for=condition=ready pod --selector=app=producer --timeout=120s

#k8s-workload-undeploy: @ Undeploy workloads from k8s
k8s-workload-undeploy: deps-k8s
	@kubectl delete -f ./k8s/producer.yaml --namespace=dapr-app --wait=true --ignore-not-found=true
	@kubectl delete -f ./k8s/consumer.yaml --namespace=dapr-app --wait=true --ignore-not-found=true
	@kubectl delete -f ./k8s/kafka-pubsub.yaml --namespace=dapr-app --wait=true --ignore-not-found=true
	@kubectl delete -f ./k8s/ns.yaml --ignore-not-found=true

#kind-deploy: @ Full KinD deploy (cluster + cloud-provider-kind + Dapr + Kafka + workloads)
kind-deploy: kind-create kind-setup k8s-dapr-deploy k8s-kafka-deploy k8s-workload-deploy
	@echo "Full KinD stack deployed."

# Alias: docker-compose-style up/down shortcuts.
#kind-up: @ Alias for kind-deploy
kind-up: kind-deploy

#kind-down: @ Alias for kind-destroy
kind-down: kind-destroy

#k8s-deploy: @ [alias] Full stack deploy (delegates to kind-deploy)
k8s-deploy: kind-deploy

#k8s-undeploy: @ Full stack undeploy (workloads + Kafka + Dapr + cluster)
k8s-undeploy: k8s-workload-undeploy k8s-kafka-undeploy k8s-dapr-undeploy kind-destroy
	@echo "Full KinD stack undeployed."

#k8s-test: @ Verify K8s deployment (pods running, messages flowing)
k8s-test: deps-k8s
	@echo "=== Checking pods in dapr-app namespace ==="
	@kubectl get pods -n dapr-app -o wide
	@echo ""
	@echo "=== Waiting for consumer to be ready ==="
	@kubectl wait --namespace dapr-app --for=condition=ready pod --selector=app=consumer --timeout=120s
	@echo ""
	@echo "=== Verifying producer container is running ==="
	@kubectl get pods -l app=producer -n dapr-app -o jsonpath='{.items[0].status.containerStatuses[?(@.name=="producer")].state.running}' | grep -q startedAt || \
		{ echo "Error: producer container not running"; kubectl logs -l app=producer -c producer -n dapr-app --tail=5; exit 1; }
	@echo "Producer container is running."
	@echo ""
	@echo "=== Producer logs (last 10 lines) ==="
	@kubectl logs -l app=producer -c producer -n dapr-app --tail=10
	@echo ""
	@echo "=== Consumer logs (last 10 lines) ==="
	@kubectl logs -l app=consumer -c consumer -n dapr-app --tail=10
	@echo ""
	@echo "=== Verifying message flow (consumer received messages) ==="
	@kubectl logs -l app=consumer -c consumer -n dapr-app --tail=50 | grep -q "Message is delivered" || \
		{ echo "Error: consumer has not received any messages yet"; exit 1; }
	@echo "Messages flowing: producer -> Kafka -> consumer via Dapr PubSub."
	@echo ""
	@echo "K8s integration test passed."

#renovate-validate: @ Validate Renovate configuration
renovate-validate: deps
	@if [ -n "$$GH_ACCESS_TOKEN" ]; then \
		GITHUB_COM_TOKEN=$$GH_ACCESS_TOKEN npx --yes renovate --platform=local; \
	else \
		echo "Warning: GH_ACCESS_TOKEN not set, some dependency lookups may fail"; \
		npx --yes renovate --platform=local; \
	fi

.PHONY: help deps-mise deps deps-k8s clean build \
	test integration-test e2e e2e-compose \
	vulncheck secrets trivy-fs trivy-config mermaid-lint deps-prune-check \
	lint static-check format ci ci-run release version \
	image-build docker-smoke-test _smoke-one local-kafka-run local-kafka-stop \
	dapr-run-producer dapr-run-consumer update \
	kind-create kind-setup kind-lb-stop kind-destroy kind-list \
	kind-deploy kind-up kind-down \
	k8s-dapr-deploy k8s-dapr-undeploy \
	k8s-kafka-deploy k8s-kafka-undeploy \
	k8s-image-load k8s-workload-deploy k8s-workload-undeploy \
	k8s-deploy k8s-undeploy k8s-test \
	renovate-validate
