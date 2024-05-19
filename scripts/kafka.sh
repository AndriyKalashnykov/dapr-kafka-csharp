#!/bin/bash

LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);
set -e
# set -x

SCRIPT_ACTION=${1:-install}
KAFKA_CLUSTER_NAME=${2:-dapr-kafka}
KAFKA_NAMESPACE=${3:-kafka}

echo $KAFKA_CLUSTER_NAME
echo $KAFKA_NAMESPACE

helm repo add bitnami https://charts.bitnami.com/bitnami
#helm repo add kafka-ui https://provectus.github.io/kafka-ui-charts
helm repo update

helm ls -n $KAFKA_NAMESPACE

SASL_ADMIN_USER=admin
SASL_ADMIN_PASSWORD=kafka-admin-password
#SASL_ADMIN_PASSWORD=$(kubectl get secret $KAFKA_CLUSTER_NAME-kafka-svcbind-user-0 --namespace $KAFKA_NAMESPACE -o jsonpath='{.data.password}' | base64 -d | cut -d , -f 1)
#SASL_ADMIN_PASSWORD=${SASL_ADMIN_PASSWORD:-$(openssl rand -hex 6)}

KAFKA_USER=kafka-client
KAFKA_PASSWORD=kafka-client-password
#KAFKA_PASSWORD=$(kubectl get secret $KAFKA_CLUSTER_NAME-kafka-svcbind-user-1 --namespace $KAFKA_NAMESPACE -o jsonpath='{.data.password}' | base64 -d | cut -d , -f 1)
#KAFKA_PASSWORD=${KAFKA_PASSWORD:-$(openssl rand -hex 6)}

# https://github.com/bitnami/charts/tree/main/bitnami/kafka#upgrading
KAFKA_VERSION="28.0.0"
#KAFKA_UI_VERSION="0.7.5"


if [[ $SCRIPT_ACTION != "install" && $SCRIPT_ACTION != "delete" ]]; then
  echo "Error: Action \"$SCRIPT_ACTION\" is not supported. Supported: 'install', 'delete'"
  exit 1
fi

if [[ $SCRIPT_ACTION == "install"  ]]; then
  ## INSTALL KAFKA
  TPM_VALUES_NAME="/tmp/tpm.kafka.values.yaml"
  sed "s/{{kafka_user}}/$KAFKA_USER/g; s/{{kafka_user_password}}/$KAFKA_PASSWORD/g; s/{{admin_user}}/$SASL_ADMIN_USER/g; s/{{kafka_admin_password}}/$SASL_ADMIN_PASSWORD/g;" $SCRIPT_PARENT_DIR/k8s/values/kafka.values.yaml > $TPM_VALUES_NAME
  
  cat  $TPM_VALUES_NAME
  
  helm upgrade --install -f $TPM_VALUES_NAME $KAFKA_CLUSTER_NAME bitnami/kafka --namespace $KAFKA_NAMESPACE --create-namespace  \
    --timeout 10m \
    --version $KAFKA_VERSION \
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
    --set kraft.enabled=true \
    --set controller.replicaCount=3 \
    --set zookeeper.enabled=false  \
    --set zookeeper.verifyHostname=false  \
    --set zookeeper.metrics.enabled=false  \
    --set zookeeper.persistence.enabled=false \
    --set zookeeper.replicaCount=0 \
    --set broker.replicaCount=0 \
    --set deleteTopicEnable=true \
    --set provisioning.enabled=true \
    --set provisioning.topics[0].name="sampletopic" \
    --set provisioning.topics[0].partitions=1 \
    --set provisioning.topics[0].replicationFactor=1 \
    --set provisioning.topics[0].config.max.message.bytes=128000 \
    --set auth.clientProtocol=sasl \
    --set allowPlaintextListener=true \
    --set advertisedListeners=SASL_PLAINTEXT://:9092 \
    --set listeners.client.protocol="SASL_PLAINTEXT" \
    --wait
  
  kubectl run $KAFKA_CLUSTER_NAME-client --restart='Never' --image docker.io/bitnami/kafka:latest --namespace $KAFKA_NAMESPACE --command -- sleep infinity
  kubectl wait --for=condition=ready pod/$KAFKA_CLUSTER_NAME-client -n $KAFKA_NAMESPACE
  kubectl cp --namespace kafka $SCRIPT_PARENT_DIR/kafka/client.properties dapr-kafka-client:/tmp/client.properties
  
  rm $TPM_VALUES_NAME
  
elif [[ $SCRIPT_ACTION == "delete" ]]; then
#	helm delete $KAFKA_CLUSTER_NAME bitnami/kafka --namespace $KAFKA_NAMESPACE
	kubectl delete pod -n $KAFKA_NAMESPACE $KAFKA_CLUSTER_NAME-client
fi
