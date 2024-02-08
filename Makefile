.DEFAULT_GOAL := help

PRODUCER_IMG ?= andriykalashnykov/producer:latest
CONSUMER_IMG ?= andriykalashnykov/consumer:latest
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

#producer-image-build: @ Build Producer Docker image
producer-image-build: build
	docker build -t ${PRODUCER_IMG} -f producer/Dockerfile .
	docker build -t ${CONSUMER_IMG} -f consumer/Dockerfile .

#producer-image-run: @ Run a Docker image
producer-image-run: producer-image-stop producer-image-build
	$(call setup_env)
	docker compose -f "docker-compose.yml" up

#producer-image-stop: @ Run a Docker image
producer-image-stop:
	docker compose -f "docker-compose.yml" down

#runp: @ Run producer
runp: build
	dotnet run --project producer/producer.csproj

#runc: @ Run consumer
runc: build
	dotnet run --project consumer/consumer.csproj

#k8s-deploy: @ Deploy to a local KinD cluster
k8s-deploy:
	@cat ./k8s/ns.yaml | kubectl apply -f - && \
	cat ./k8s/deployment.yaml | kubectl apply --namespace=kafka-confluent-examples -f - && \
	cat ./k8s/service.yaml | kubectl apply --namespace=kafka-confluent-examples -f -

#k8s-undeploy: @ Undeploy from a local KinD cluster
k8s-undeploy:
	@kubectl delete -f ./k8s/deployment.yaml --namespace=kafka-confluent-examples --ignore-not-found=true && \
	kubectl delete -f ./k8s/service.yaml --namespace=kafka-confluent-examples --ignore-not-found=true && \
	kubectl delete -f ./k8s/ns.yaml --ignore-not-found=true

# upgrade outdated https://github.com/NuGet/Home/issues/4103
upgrade:
	cd consumer && dotnet list package --outdated | grep -o '> \S.' | grep '[^> ].' -o | awk '{system("dotnet add package "$1 " -v " $4)}'
	cd models && dotnet list package --outdated | grep -o '> \S.' | grep '[^> ].' -o | awk '{system("dotnet add package "$1 " -v " $4)}'
	cd producer && dotnet list package --outdated | grep -o '> \S.' | grep '[^> ].' -o | awk '{system("dotnet add package "$1 " -v " $4)}'

# ssh into pod
# kubectl exec --stdin --tty -n kafka-confluent-examples kafka-confluent-go-56686b9958-ft2bh -- /bin/sh

# pod logs
# kubectl logs -n kafka-confluent-examples kafka-confluent-go-56686b9958-ft2bh --follow --timestamps
