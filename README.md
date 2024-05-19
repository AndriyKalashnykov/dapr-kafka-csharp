# Producer and Consumer examples using Dapr Pubsub

## Pre-requisites

1. [Install Docker](https://www.docker.com/products/docker-desktop)
2. [Install Dapr CLI](https://docs.dapr.io/getting-started/install-dapr-cli/)
3. [Install .Net Core SDK 8.0](https://dotnet.microsoft.com/download)

```bash
dotnet --list-sdks
dotnet --list-runtimes

sudo apt-get install -y dotnet-sdk-8.0
sudo apt-get install -y dotnet-host 
sudo apt-get install -y aspnetcore-runtime-8.0
sudo apt-get install -y dotnet-runtime-8.0
dotnet sdk check
dotnet --list-sdks
dotnet --list-runtimes


sudo apt remove dotnet-sdk* dotnet-host* dotnet* aspnetcore* netstandard*
sudo apt remove aspnetcore*
sudo apt remove netstandard*
sudo apt remove dotnet-host*
sudo apt purge dotnet-sdk* dotnet-host* dotnet* aspnetcore* netstandard*
sudo rm -f /etc/apt/sources.list.d/mssql-release.list
sudo rm /etc/apt/sources.list.d/microsoft-prod.list
sudo rm /etc/apt/sources.list.d/microsoft-prod.list.save
sudo apt update
sudo apt-get install -y dotnet-sdk-8.0
sudo apt-get install -y dotnet-host 
sudo apt-get install -y aspnetcore-runtime-8.0
sudo apt-get install -y dotnet-runtime-8.0
dotnet workload update
source ~/.bashrc
dotnet sdk check
```

4. Clone the sample repo

```
git clone https://github.com/andriykalashnykov/dapr-kafka-csharp.git
```

## Running locally

### Install Dapr in standalone mode

1. [Install Dapr in standalone mode](https://github.com/dapr/docs/blob/master/getting-started/environment-setup.md#installing-dapr-in-standalone-mode)

```
$ dapr init
```

### Run Kafka Docker Container Locally

In order to run the Kafka bindings sample locally, you will run
the [Kafka broker server](https://github.com/wurstmeister/kafka-docker) in a docker container on your machine. Make sure
docker is running in Linux mode.

1. Run `docker-compose -f ./docker-compose-kafka.yaml up -d` to run the container locally
2. Run `docker ps` to see the container running locally:

```bash
CONTAINER ID        IMAGE                           COMMAND                  CREATED             STATUS              PORTS                                                NAMES
aaa142160487        wurstmeister/zookeeper:latest   "/bin/sh -c '/usr/sb…"   2 minutes ago       Up 2 minutes        22/tcp, 2888/tcp, 3888/tcp, 0.0.0.0:2181->2181/tcp   dapr-kafka-csharp_zookeeper_1
0e3908026eda        wurstmeister/kafka:latest       "start-kafka.sh"         2 minutes ago       Up 2 minutes        0.0.0.0:9092->9092/tcp                               dapr-kafka-csharp_kafka_1
c0c3ca47c0ad        daprio/dapr                     "./placement"            3 days ago          Up 32 hours         0.0.0.0:50005->50005/tcp                             dapr_placement
c8eec02b4e5d        redis                           "docker-entrypoint.s…"   3 days ago          Up 32 hours         0.0.0.0:6379->6379/tcp                               dapr_redis
```

### Run Consumer app

```
cd consumer
dapr run --app-id consumer --app-port 6000 -- dotnet run
```

### Run Producer app

```
cd producer
dapr run --app-id producer --resources-path ./deploy -- dotnet run
```

### Uninstall Kafka

```
docker-compose -f ./docker-compose-kafka.yaml down
```

## Run in Kubernetes cluster

### Install Dapr on Kubernetes

```
dapr init -k

⌛  Making the jump to hyperspace...
ℹ️  Note: this installation is recommended for testing purposes. For production environments, please use Helm 

✅  Deploying the Dapr control plane to your cluster...
✅  Success! Dapr has been installed. To verify, run 'kubectl get pods -w' or 'dapr status -k' in your terminal. To get started, go here: https://aka.ms/dapr-getting-started

kubectl get pods -w

NAME                                     READY   STATUS    RESTARTS   AGE
dapr-operator-6bdc6f95c6-g67p2           1/1     Running   0          37s
dapr-placement-fb75fb85-k6m7d            1/1     Running   0          37s
dapr-sentry-6f796dd4cb-rh9qx             1/1     Running   0          37s
dapr-sidecar-injector-7bc488df76-jg6fw   1/1     Running   0          37s
```

Dapr Dashboard

```bash
dapr dashboard -k
```

> For more detail, refer
>
to [Dapr in Kubernetes environment](https://github.com/dapr/docs/blob/master/getting-started/environment-setup.md#installing-dapr-on-a-kubernetes-cluster)
> for more detail.
> For helm users, please refer
> to [this](https://github.com/dapr/docs/blob/master/getting-started/environment-setup.md#using-helm-advanced).

### Setting up a Kafka in Kubernetes

1. Install Kafka

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install dapr-kafka bitnami/kafka --namespace kafka --create-namespace  \
  --set image.tag=latest \
  --set persistence.storageClass=standard \
  --set controller.persistence.enabled=true \
  --set controller.persistence.size=4Gi \
  --set broker.persistence.enabled=true \
  --set broker.persistence.size=4Gi \
  --set broker.logPersistence.enabled=true \
  --set broker.logPersistence.size=4Gi \
  --set metrics.kafka.enabled=false \
  --set metrics.jmx.enabled=false \
  --set serviceAccount.create=true \
  --set rbac.create=true \
  --set service.type=ClusterIP \
  --set kraft.enabled=false \
  --set controller.replicaCount=1 \
  --set zookeeper.metrics.enabled=false  \
  --set zookeeper.enabled=false \
  --set zookeeper.persistence.enabled=false \
  --set zookeeper.replicaCount=1 \
  --set broker.replicaCount=1 \
  --set replicaCount=1 \
  --set deleteTopicEnable=true \
  --set auth.clientProtocol=sasl \
  --set authorizerClassName="kafka.security.authorizer.AclAuthorizer" \
  --set allowPlaintextListener=true \
  --set advertisedListeners=PLAINTEXT://:9092 \
  --set listenerSecurityProtocolMap=PLAINTEXT:PLAINTEXT \
  --wait
```

```text
Kafka can be accessed by consumers via port 9092 on the following DNS name from within your cluster:

    dapr-kafka.kafka.svc.cluster.local

Each Kafka broker can be accessed by producers via port 9092 on the following DNS name(s) from within your cluster:

    dapr-kafka-controller-0.dapr-kafka-controller-headless.kafka.svc.cluster.local:9092
    dapr-kafka-broker-0.dapr-kafka-broker-headless.kafka.svc.cluster.local:9092

The CLIENT listener for Kafka client connections from within your cluster have been configured with the following security settings:
    - SASL authentication

To connect a client to your Kafka, you need to create the 'client.properties' configuration files with the content below:

security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-256
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required \
    username="user1" \
    password="$(kubectl get secret dapr-kafka-user-passwords --namespace kafka -o jsonpath='{.data.client-passwords}' | base64 -d | cut -d , -f 1)";

To create a pod that you can use as a Kafka client run the following commands:

    kubectl run dapr-kafka-client --restart='Never' --image docker.io/bitnami/kafka:latest --namespace kafka --command -- sleep infinity
    kubectl cp --namespace kafka ./kafka/client.properties dapr-kafka-client:/tmp/client.properties
    kubectl exec --tty -i dapr-kafka-client --namespace kafka -- bash

    PRODUCER:
        kafka-console-producer.sh \
            --producer.config /tmp/client.properties \
            --broker-list dapr-kafka-broker-0.dapr-kafka-broker-headless.kafka.svc.cluster.local:9092 \
            --topic test

    CONSUMER:
        kafka-console-consumer.sh \
            --consumer.config /tmp/client.properties \
            --bootstrap-server dapr-kafka.kafka.svc.cluster.local:9092 \
            --topic test \
            --from-beginning
```

2. Wait until kafka pods are running

```
kubectl get pods -n kafka -w
NAME                     READY   STATUS    RESTARTS   AGE
dapr-kafka-0             1/1     Running   0          2m7s
dapr-kafka-zookeeper-0   1/1     Running   0          2m57s
dapr-kafka-zookeeper-1   1/1     Running   0          2m13s
dapr-kafka-zookeeper-2   1/1     Running   0          109s
```

3. Deploy the producer and consumer applications to Kubernetes

```
make image-build
docker image save -o consumer-v1.0.0.tar andriykalashnykov/consumer:v1.0.0
minikube image load consumer-v1.0.0.tar --profile dapr

docker image save -o producer-v1.0.0.tar andriykalashnykov/producer:v1.0.0
minikube image load producer-v1.0.0.tar --profile dapr

minikube image ls -p dapr | grep andriykalashnykov/

minikube image rm andriykalashnykov/consumer:v1.0.0 --profile dapr
minikube image rm andriykalashnykov/producer:v1.0.0 --profile dapr
minikube image load andriykalashnykov/consumer:v1.0.0 --profile dapr
minikube image load andriykalashnykov/producer:v1.0.0 --profile dapr

kubectl describe replicaset producer-
kubectl describe replicaset consumer-

kubectl apply -f ./deploy/kafka-pubsub.yaml
kubectl apply -f ./deploy/producer.yaml
kubectl apply -f ./deploy/consumer.yaml

kubectl delete -f ./deploy/kafka-pubsub.yaml
kubectl delete -f ./deploy/consumer.yaml
kubectl delete -f ./deploy/producer.yaml
```

4. Check the logs from producer and consumer:

```
kubectl logs -f -l app=producer -c producer -n dapr-app
kubectl logs -f -l app=consumer -c consumer -n dapr-app
```

## Build and push docker image to your docker registry

1. Create your docker hub account or use your own docker registry

2. Build Docker images.

```sh
docker build -t [docker_registry]/consumer:latest -f ./consumer/Dockerfile .
docker build -t [docker_registry]/producer:latest -f ./producer/Dockerfile .
```

3. Push Docker images.

```sh
docker push [docker_registry]/consumer:latest
docker push [docker_registry]/producer:latest
```

4. Update image names

* Update imagename to [docker_registry]/consumer:latest
  in [deploy/consumer.yaml](https://github.com/andriykalashnykov/dapr-kafka-csharp/blob/master/deploy/consumer.yaml#L39)
* Update imagename to [docker_registry]/producer:latest
  in [deploy/producer.yaml](https://github.com/andriykalashnykov/dapr-kafka-csharp/blob/master/deploy/producer.yaml#L23)

## Cleanup

1. Stop the applications

```
kubectl delete -f ./deploy/kafka-pubsub.yaml
kubectl delete -f ./deploy/consumer.yaml
kubectl delete -f ./deploy/producer.yaml
```

2. Uninstall Kafka

```
helm uninstall dapr-kafka -n kafka
```

3. Uninstall Dapr

```
dapr uninstall -k
```
