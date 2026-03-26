.DEFAULT_GOAL := help

APP_NAME       := dapr-kafka-csharp
CURRENTTAG     := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")

# === Tool Versions (pinned) ===
DAPR_VERSION   := 1.15.3

# === Project Paths ===
SOLUTION       := dapr-kafka-csharp.slnx
PRODUCER_IMG   ?= andriykalashnykov/producer:v1.0.0
CONSUMER_IMG   ?= andriykalashnykov/consumer:v1.0.0

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-20s\033[0m - %s\n", $$1, $$2}'

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
build: deps clean
	@dotnet build "$(SOLUTION)"

#test: @ Run tests
test: deps
	@dotnet test "$(SOLUTION)" -c Release --nologo -v q

#lint: @ Check code formatting
lint: deps
	@dotnet format "$(SOLUTION)" --verify-no-changes

#format: @ Auto-fix code formatting
format: deps
	@dotnet format "$(SOLUTION)"

#ci: @ Run full local CI pipeline
ci: deps build lint test
	@echo "Local CI pipeline passed."

#release: @ Create and push a new tag
release:
	@bash -c 'read -p "New tag (current: $(CURRENTTAG)): " newtag && \
		echo "$$newtag" | grep -qE "^v[0-9]+\.[0-9]+\.[0-9]+$$" || { echo "Error: Tag must match vN.N.N"; exit 1; } && \
		echo -n "Create and push $$newtag? [y/N] " && read ans && [ "$${ans:-N}" = y ] && \
		echo $$newtag > ./version.txt && \
		git add -A && \
		git commit -a -s -m "Cut $$newtag release" && \
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
update:
	@for proj in consumer models producer; do \
		cd $$proj && dotnet list package --outdated | grep -o '> \S*' | grep '[^> ]*' -o | xargs --no-run-if-empty -L 1 dotnet add package; \
		cd ..; \
	done

#minikube-start: @ Start Minikube
minikube-start:
	@./scripts/minikube.sh start

#minikube-stop: @ Stop Minikube
minikube-stop:
	@./scripts/minikube.sh stop

#minikube-delete: @ Delete Minikube
minikube-delete:
	@./scripts/minikube.sh delete

#minikube-list: @ List Minikube profiles
minikube-list:
	@minikube profile list

#https://docs.dapr.io/operations/hosting/kubernetes/kubernetes-deploy/#install-dapr-from-the-official-dapr-helm-chart-with-development-flag
#k8s-dapr-deploy: @ Deploy DAPR to k8s
k8s-dapr-deploy:
	@helm repo add dapr https://dapr.github.io/helm-charts/ && \
	helm repo update && \
	helm upgrade --install dapr dapr/dapr --set version=$(DAPR_VERSION) --namespace dapr-system --create-namespace --wait && \
	helm upgrade --install dapr-dashboard dapr/dapr-dashboard --set version=$(DAPR_VERSION) --namespace dapr-system --set serviceType=LoadBalancer --wait && \
	kubectl get pods --namespace dapr-system
# kubectl port-forward svc/dapr-dashboard 8080:8080 -n dapr-system
# xdg-open http://localhost:8080

#k8s-dapr-undeploy: @ Undeploy DAPR from k8s
k8s-dapr-undeploy:
	@helm uninstall dapr --namespace dapr-system && \
	helm uninstall dapr-dashboard --namespace dapr-system

#k8s-kafka-deploy: @ Deploy Kafka to k8s
k8s-kafka-deploy:
	@./scripts/kafka.sh install

#k8s-kafka-undeploy: @ Undeploy Kafka from k8s
k8s-kafka-undeploy:
	@./scripts/kafka.sh delete

#k8s-image-load: @ Image load to k8s
k8s-image-load: image-build
	@minikube image rm $(CONSUMER_IMG) --profile dapr && \
	minikube image rm $(PRODUCER_IMG) --profile dapr && \
	minikube image load $(CONSUMER_IMG) --profile dapr && \
	minikube image load $(PRODUCER_IMG) --profile dapr && \
	minikube image ls -p dapr | grep andriykalashnykov/

#k8s-workload-deploy: @ Deploy workloads to k8s
k8s-workload-deploy: k8s-image-load
	@cat ./k8s/ns.yaml | kubectl apply -f - && \
	cat ./k8s/kafka-pubsub.yaml | kubectl apply --namespace=dapr-app --wait=true -f - && \
	cat ./k8s/producer.yaml | kubectl apply --namespace=dapr-app --wait=true -f - && \
	cat ./k8s/consumer.yaml | kubectl apply --namespace=dapr-app --wait=true -f - && \
	kubectl wait --namespace dapr-app --for=condition=ready pod --selector=app=consumer --timeout=120s && \
	kubectl logs -f -l app=consumer -c consumer -n dapr-app

#k8s-workload-undeploy: @ Undeploy workloads from k8s
k8s-workload-undeploy:
	@kubectl delete -f ./k8s/producer.yaml --namespace=dapr-app --wait=true --ignore-not-found=true && \
	kubectl delete -f ./k8s/consumer.yaml --namespace=dapr-app --wait=true --ignore-not-found=true && \
	kubectl delete -f ./k8s/kafka-pubsub.yaml --namespace=dapr-app --wait=true --ignore-not-found=true && \
	kubectl delete -f ./k8s/ns.yaml --ignore-not-found=true

# ssh into pod
# kubectl exec --stdin --tty -n kafka-confluent-examples kafka-confluent-go-56686b9958-ft2bh -- /bin/sh

# pod logs
# kubectl logs -n kafka-confluent-examples kafka-confluent-go-56686b9958-ft2bh --follow --timestamps

.PHONY: help deps clean build test lint format ci release version \
	image-build local-kafka-run local-kafka-stop \
	dapr-run-producer dapr-run-consumer update \
	minikube-start minikube-stop minikube-delete minikube-list \
	k8s-dapr-deploy k8s-dapr-undeploy \
	k8s-kafka-deploy k8s-kafka-undeploy \
	k8s-image-load k8s-workload-deploy k8s-workload-undeploy
