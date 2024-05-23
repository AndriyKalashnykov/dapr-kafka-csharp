.DEFAULT_GOAL := help

PRODUCER_IMG ?= andriykalashnykov/producer:v1.0.0
CONSUMER_IMG ?= andriykalashnykov/consumer:v1.0.0
CURRENTTAG:=$(shell git describe --tags --abbrev=0)
NEWTAG ?= $(shell bash -c 'read -p "Please provide a new tag (currnet tag - ${CURRENTTAG}): " newtag; echo $$newtag')

#help: @ List available tasks
help:
	@clear
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-20s\033[0m - %s\n", $$1, $$2}'

#clean: @ Cleanup
clean:
	@rm -rf ./consumer/bin/ ./consumer/obj/
	@rm -rf ./models/bin/ ./models/obj/
	@rm -rf ./producer/bin/ ./producer/obj/

#build: @ Build
build: clean
	cd consumer && dotnet build consumer.csproj && cd ..
	cd models && dotnet build models.csproj && cd ..
	cd producer && dotnet build producer.csproj && cd ..


#release: @ Create and push a new tag
release:
	$(eval NT=$(NEWTAG))
	@echo -n "Are you sure to create and push ${NT} tag? [y/N] " && read ans && [ $${ans:-N} = y ]
	@echo ${NT} > ./version.txt
	@git add -A
	@git commit -a -s -m "Cut ${NT} release"
	@git tag ${NT}
	@git push origin ${NT}
	@git push
	@echo "Done."

#version: @ Print current version(tag)
version:
	@echo $(shell git describe --tags --abbrev=0)

#image-build: @ Build Docker images
image-build:
	docker build -t ${PRODUCER_IMG} -f producer/Dockerfile .
	docker build -t ${CONSUMER_IMG} -f consumer/Dockerfile .

# Kafka in Docker
# https://jaehyeon.me/blog/2023-07-06-kafka-development-with-docker-part-9/
# https://github.com/jaehyeon-kim/kafka-pocs/tree/main/kafka-dev-with-docker/part-09
#local-kafka-run: @ Run a local Kafka instance
local-kafka-run: local-kafka-stop
	docker compose -f "docker-compose.yaml" up

#local-kafka-stop: @ Stop a local Kafka instance
local-kafka-stop:
	docker compose -f "docker-compose.yaml" down

#runp: @ Run producer
runp: build
	dotnet run --project producer/producer.csproj

#runc: @ Run consumer
runc: build
	dotnet run --project consumer/consumer.csproj

# upgrade outdated https://github.com/NuGet/Home/issues/4103
# https://github.com/dotnet-outdated/dotnet-outdated
# dotnet tool update --global dotnet-outdated-tool

#upgrade: @ Upgrade outdated packages
upgrade:
	@cd consumer && dotnet list package --outdated | grep -o '> \S*' | grep '[^> ]*' -o | xargs --no-run-if-empty -L 1 dotnet add package
	@cd models && dotnet list package --outdated | grep -o '> \S*' | grep '[^> ]*' -o | xargs --no-run-if-empty -L 1 dotnet add package
	@cd producer && dotnet list package --outdated | grep -o '> \S*' | grep '[^> ]*' -o | xargs --no-run-if-empty -L 1 dotnet add package

#minikube-start: @ Start Minikube, parametrized example: ./scripts/minikube.sh start dapr 1 8000mb 2 40g docker 192.168.200.200
minikube-start:
	./scripts/minikube.sh start

#minikube-stop: @ Stop Minikube
minikube-stop:
	./scripts/minikube.sh stop

#minikube-delete: @ Delete Minikube
minikube-delete: 
	./scripts/minikube.sh delete

#minikube-list: @ List Minikube profiles
minikube-list: 
	minikube profile list

#https://docs.dapr.io/operations/hosting/kubernetes/kubernetes-deploy/#install-dapr-from-the-official-dapr-helm-chart-with-development-flag
#k8s-dapr-deploy: @ Deploy DAPR to k8s
k8s-dapr-deploy:
	helm repo add dapr https://dapr.github.io/helm-charts/ && \
	helm repo update && \
	helm upgrade --install dapr dapr/dapr --version=1.13 --namespace dapr-system --create-namespace --wait && \
	kubectl get pods --namespace dapr-system

#k8s-dapr-undeploy: @ Undeploy DAPR from k8s
k8s-dapr-undeploy:
	helm uninstall dapr --namespace dapr-system

#k8s-kafka-deploy: @ Deploy Kafka to k8s
k8s-kafka-deploy:
	./scripts/kafka.sh install

#k8s-kafka-undeploy: @ Undeploy Kafka from k8s
k8s-kafka-undeploy:
	./scripts/kafka.sh delete

#k8s-image-load: @ Image load to k8s
k8s-image-load: image-build
	@minikube image rm ${CONSUMER_IMG} --profile dapr  && \
    minikube image rm ${PRODUCER_IMG} --profile dapr  && \
    minikube image load ${CONSUMER_IMG} --profile dapr  && \
    minikube image load ${PRODUCER_IMG} --profile dapr  && \
    minikube image ls -p dapr | grep andriykalashnykov/

#k8s-workload-deploy: @ Deploy workloads to k8s
k8s-workload-deploy: k8s-image-load
	@cat ./k8s/ns.yaml | kubectl apply -f - && \
	cat ./k8s/kafka-pubsub.yaml | kubectl apply --namespace=dapr-app --wait=true -f - && \
	cat ./k8s/producer.yaml | kubectl apply --namespace=dapr-app --wait=true -f - && \
	cat ./k8s/consumer.yaml | kubectl apply --namespace=dapr-app --wait=true -f - && \
	kubectl wait --namespace dapr-app --for=condition=ready pod --selector=app=consumer --timeout=120s && \
	kubectl logs -f -l app=consumer -c consumer -n dapr-app
#	kubectl logs -f -l app=producer -c producer -n dapr-app
#	kubectl wait --namespace dapr-app --for=condition=ready pod --selector=app=producer --timeout=120s && \


#k8s-workload-undeploy: @ Undeploy workloads form k8s
k8s-workload-undeploy:
	@kubectl delete -f ./k8s/producer.yaml --namespace=dapr-app --wait=true --ignore-not-found=true && \
	kubectl delete -f ./k8s/consumer.yaml --namespace=dapr-app --wait=true --ignore-not-found=true && \
	kubectl delete -f ./k8s/kafka-pubsub.yaml --namespace=dapr-app --wait=true --ignore-not-found=true && \
	kubectl delete -f ./k8s/ns.yaml --ignore-not-found=true

# ssh into pod
# kubectl exec --stdin --tty -n kafka-confluent-examples kafka-confluent-go-56686b9958-ft2bh -- /bin/sh

# pod logs
# kubectl logs -n kafka-confluent-examples kafka-confluent-go-56686b9958-ft2bh --follow --timestamps
