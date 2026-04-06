.DEFAULT_GOAL := help

APP_NAME       := dapr-kafka-csharp
CURRENTTAG     := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")

# === Tool Versions (pinned) ===
DAPR_VERSION     := 1.17.3
ACT_VERSION      := 0.2.87
NVM_VERSION      := 0.40.4
HADOLINT_VERSION := 2.14.0
NODE_VERSION     := 24

# === Minikube Settings ===
MINIKUBE_PROFILE := dapr-dotnet

# === Project Paths ===
SOLUTION       := dapr-kafka-csharp.slnx
PRODUCER_IMG   ?= andriykalashnykov/producer:v1.0.0
CONSUMER_IMG   ?= andriykalashnykov/consumer:v1.0.0

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-25s\033[0m - %s\n", $$1, $$2}'

#deps: @ Check required tools
deps:
	@command -v dotnet >/dev/null 2>&1 || { echo "Error: .NET SDK required. See https://dotnet.microsoft.com/download"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "Error: Docker required. See https://docs.docker.com/get-docker/"; exit 1; }

#clean: @ Remove build artifacts
clean:
	@dotnet clean "$(SOLUTION)" -v q --nologo
	@rm -rf ./consumer/bin/ ./consumer/obj/
	@rm -rf ./models/bin/ ./models/obj/
	@rm -rf ./producer/bin/ ./producer/obj/

#build: @ Build the solution
build: deps
	@dotnet build "$(SOLUTION)" --nologo -v q

#test: @ Run tests
test: deps
	@dotnet test "$(SOLUTION)" -c Release --nologo -v q

#deps-k8s: @ Check Kubernetes tools (minikube, kubectl, helm, dapr)
deps-k8s: deps
	@command -v minikube >/dev/null 2>&1 || { echo "Error: minikube required. See https://minikube.sigs.k8s.io/"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl required. See https://kubernetes.io/docs/tasks/tools/"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "Error: Helm required. See https://helm.sh/"; exit 1; }
	@command -v dapr >/dev/null 2>&1 || { echo "Error: Dapr CLI required. See https://docs.dapr.io/getting-started/install-dapr-cli/"; exit 1; }

#deps-hadolint: @ Install hadolint for Dockerfile linting
deps-hadolint: deps
	@command -v hadolint >/dev/null 2>&1 || { echo "Installing hadolint $(HADOLINT_VERSION)..."; \
		curl -sSfL -o /tmp/hadolint https://github.com/hadolint/hadolint/releases/download/v$(HADOLINT_VERSION)/hadolint-Linux-x86_64 && \
		install -m 755 /tmp/hadolint /usr/local/bin/hadolint && \
		rm -f /tmp/hadolint; \
	}

#lint: @ Check code formatting and lint Dockerfiles
lint: deps deps-hadolint
	@dotnet format "$(SOLUTION)" --verify-no-changes
	@dotnet build "$(SOLUTION)" -warnaserror --nologo -v q
	@hadolint consumer/Dockerfile
	@hadolint producer/Dockerfile

#format: @ Auto-fix code formatting
format: deps
	@dotnet format "$(SOLUTION)"

#ci: @ Run full local CI pipeline
ci: deps lint build test
	@echo "Local CI pipeline passed."

#deps-act: @ Install act for local CI
deps-act: deps
	@command -v act >/dev/null 2>&1 || { echo "Installing act $(ACT_VERSION)..."; \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash -s -- -b /usr/local/bin v$(ACT_VERSION); \
	}

#ci-run: @ Run GitHub Actions workflow locally via act
ci-run: deps-act
	@act push --container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts

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
image-build: deps
	@docker buildx build --load -t $(PRODUCER_IMG) -f producer/Dockerfile .
	@docker buildx build --load -t $(CONSUMER_IMG) -f consumer/Dockerfile .

# Kafka in Docker
# https://jaehyeon.me/blog/2023-07-06-kafka-development-with-docker-part-9/
# https://github.com/jaehyeon-kim/kafka-pocs/tree/main/kafka-dev-with-docker/part-09
#local-kafka-run: @ Run a local Kafka instance
local-kafka-run: local-kafka-stop
	@docker compose -f "docker-compose.yaml" up

#local-kafka-stop: @ Stop a local Kafka instance
local-kafka-stop:
	@docker compose -f "docker-compose.yaml" down

#dapr-run-producer: @ Run producer
dapr-run-producer: build
	@dotnet run --project producer/producer.csproj

#dapr-run-consumer: @ Run consumer
dapr-run-consumer: build
	@dotnet run --project consumer/consumer.csproj

# upgrade outdated https://github.com/NuGet/Home/issues/4103
# https://github.com/dotnet-outdated/dotnet-outdated
# dotnet tool update --global dotnet-outdated-tool

#update: @ Update outdated NuGet packages
update: deps
	@for proj in consumer models producer; do \
		cd $$proj && dotnet list package --outdated | grep -o '> \S*' | grep '[^> ]*' -o | xargs --no-run-if-empty -L 1 dotnet add package; \
		cd ..; \
	done

#minikube-start: @ Start Minikube
minikube-start: deps-k8s
	@./scripts/minikube.sh start

#minikube-stop: @ Stop Minikube
minikube-stop: deps-k8s
	@./scripts/minikube.sh stop

#minikube-delete: @ Delete Minikube
minikube-delete: deps-k8s
	@./scripts/minikube.sh delete

#minikube-list: @ List Minikube profiles
minikube-list: deps-k8s
	@minikube profile list

#https://docs.dapr.io/operations/hosting/kubernetes/kubernetes-deploy/#install-dapr-from-the-official-dapr-helm-chart-with-development-flag
#k8s-dapr-deploy: @ Deploy Dapr to k8s
k8s-dapr-deploy: deps-k8s
	@helm repo add dapr https://dapr.github.io/helm-charts/ && \
	helm repo update && \
	helm upgrade --install dapr dapr/dapr --set version=$(DAPR_VERSION) --namespace dapr-system --create-namespace --wait && \
	helm upgrade --install dapr-dashboard dapr/dapr-dashboard --set version=$(DAPR_VERSION) --namespace dapr-system --set serviceType=LoadBalancer --wait && \
	kubectl get pods --namespace dapr-system
# kubectl port-forward svc/dapr-dashboard 8080:8080 -n dapr-system
# xdg-open http://localhost:8080

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

#k8s-image-load: @ Build and load images into Minikube
k8s-image-load: deps-k8s image-build
	@minikube image rm $(CONSUMER_IMG) --profile $(MINIKUBE_PROFILE) 2>/dev/null || true
	@minikube image rm $(PRODUCER_IMG) --profile $(MINIKUBE_PROFILE) 2>/dev/null || true
	@minikube image load $(CONSUMER_IMG) --profile $(MINIKUBE_PROFILE)
	@minikube image load $(PRODUCER_IMG) --profile $(MINIKUBE_PROFILE)
	@minikube image ls -p $(MINIKUBE_PROFILE) | grep andriykalashnykov/

#k8s-workload-deploy: @ Deploy workloads to k8s
k8s-workload-deploy: k8s-image-load
	@kubectl apply -f ./k8s/ns.yaml
	@kubectl apply -f ./k8s/kafka-pubsub.yaml --namespace=dapr-app --wait=true
	@kubectl apply -f ./k8s/producer.yaml --namespace=dapr-app --wait=true
	@kubectl apply -f ./k8s/consumer.yaml --namespace=dapr-app --wait=true
	@kubectl wait --namespace dapr-app --for=condition=ready pod --selector=app=consumer --timeout=120s
	@kubectl wait --namespace dapr-app --for=condition=ready pod --selector=app=producer --timeout=120s

#k8s-workload-undeploy: @ Undeploy workloads from k8s
k8s-workload-undeploy: deps-k8s
	@kubectl delete -f ./k8s/producer.yaml --namespace=dapr-app --wait=true --ignore-not-found=true
	@kubectl delete -f ./k8s/consumer.yaml --namespace=dapr-app --wait=true --ignore-not-found=true
	@kubectl delete -f ./k8s/kafka-pubsub.yaml --namespace=dapr-app --wait=true --ignore-not-found=true
	@kubectl delete -f ./k8s/ns.yaml --ignore-not-found=true

#k8s-deploy: @ Full K8s deploy (Dapr + Kafka + workloads)
k8s-deploy: minikube-start k8s-dapr-deploy k8s-kafka-deploy k8s-workload-deploy
	@echo "Full K8s stack deployed."

#k8s-undeploy: @ Full K8s undeploy (workloads + Kafka + Dapr)
k8s-undeploy: k8s-workload-undeploy k8s-kafka-undeploy k8s-dapr-undeploy
	@echo "Full K8s stack undeployed."

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
	@echo "Messages flowing: producer → Kafka → consumer via Dapr PubSub."
	@echo ""
	@echo "K8s integration test passed."

#renovate-bootstrap: @ Install nvm and npm for Renovate
renovate-bootstrap:
	@command -v node >/dev/null 2>&1 || { \
		echo "Installing nvm $(NVM_VERSION) + Node $(NODE_VERSION)..."; \
		if [ ! -s "$$HOME/.nvm/nvm.sh" ]; then \
			curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$(NVM_VERSION)/install.sh | bash; \
		fi; \
		export NVM_DIR="$$HOME/.nvm"; \
		[ -s "$$NVM_DIR/nvm.sh" ] && . "$$NVM_DIR/nvm.sh"; \
		nvm install $(NODE_VERSION); \
	}

#renovate-validate: @ Validate Renovate configuration
renovate-validate: renovate-bootstrap
	@if [ -n "$$GH_ACCESS_TOKEN" ]; then \
		GITHUB_COM_TOKEN=$$GH_ACCESS_TOKEN npx --yes renovate --platform=local; \
	else \
		echo "Warning: GH_ACCESS_TOKEN not set, some dependency lookups may fail"; \
		npx --yes renovate --platform=local; \
	fi

# ssh into pod
# kubectl exec --stdin --tty -n kafka-confluent-examples kafka-confluent-go-56686b9958-ft2bh -- /bin/sh

# pod logs
# kubectl logs -n kafka-confluent-examples kafka-confluent-go-56686b9958-ft2bh --follow --timestamps

.PHONY: help deps deps-act deps-hadolint deps-k8s clean build test lint format ci ci-run release version \
	image-build local-kafka-run local-kafka-stop \
	dapr-run-producer dapr-run-consumer update \
	minikube-start minikube-stop minikube-delete minikube-list \
	k8s-dapr-deploy k8s-dapr-undeploy \
	k8s-kafka-deploy k8s-kafka-undeploy \
	k8s-image-load k8s-workload-deploy k8s-workload-undeploy \
	k8s-deploy k8s-undeploy k8s-test \
	renovate-bootstrap renovate-validate
