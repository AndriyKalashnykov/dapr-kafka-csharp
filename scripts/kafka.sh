#!/usr/bin/env bash
# Install or uninstall an upstream Apache Kafka cluster on KinD via the Strimzi operator.
# Replaces the legacy Bitnami chart path (frozen `bitnamilegacy/kafka` archive image).
#
# Inputs:
#   $1 — action: install | delete (default: install)
# Env from Makefile:
#   STRIMZI_OPERATOR_VERSION — Helm chart version of strimzi-kafka-operator (Renovate-tracked)
#   KIND_CLUSTER_NAME        — when set, every kubectl/helm call binds to --context=kind-<name>
#                              (prevents cross-cluster bleed when other KinD projects share ~/.kube/config)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ACTION="${1:-install}"
NAMESPACE="kafka"
RELEASE_NAME="strimzi-kafka-operator"

if [[ "${ACTION}" != "install" && "${ACTION}" != "delete" ]]; then
    echo "Error: action must be 'install' or 'delete' (got: ${ACTION})" >&2
    exit 1
fi

# Context-bound CLI invocations. The :+ form leaves the array empty when
# KIND_CLUSTER_NAME is unset, so the script also works against any current-context.
KUBECTL=(kubectl ${KIND_CLUSTER_NAME:+--context=kind-${KIND_CLUSTER_NAME}})
HELM_CTX=(${KIND_CLUSTER_NAME:+--kube-context kind-${KIND_CLUSTER_NAME}})

if [[ "${ACTION}" == "install" ]]; then
    : "${STRIMZI_OPERATOR_VERSION:?STRIMZI_OPERATOR_VERSION must be exported by the calling Makefile}"

    echo "==> Installing Strimzi operator ${STRIMZI_OPERATOR_VERSION} into ${NAMESPACE}"
    helm "${HELM_CTX[@]}" repo add strimzi https://strimzi.io/charts/
    helm "${HELM_CTX[@]}" repo update strimzi
    # Strimzi watches its own namespace by default — do NOT set --set watchNamespaces
    # to the same namespace as the release; the chart then tries to create both the
    # release-namespace RoleBindings AND the watch-namespace RoleBindings, which
    # collide on identical names ("strimzi-cluster-operator-watched" et al.) and
    # fail the install.
    helm "${HELM_CTX[@]}" upgrade --install "${RELEASE_NAME}" strimzi/strimzi-kafka-operator \
        --version "${STRIMZI_OPERATOR_VERSION}" \
        --namespace "${NAMESPACE}" --create-namespace \
        --wait

    echo "==> Applying Kafka CRs (KafkaNodePool + Kafka + KafkaTopic)"
    "${KUBECTL[@]}" apply -n "${NAMESPACE}" -f "${REPO_ROOT}/k8s/strimzi-kafka.yaml"

    echo "==> Waiting for Kafka cluster Ready"
    "${KUBECTL[@]}" wait kafka/dapr-kafka -n "${NAMESPACE}" \
        --for=condition=Ready --timeout=300s

    echo "==> Waiting for KafkaTopic sampletopic Ready"
    "${KUBECTL[@]}" wait kafkatopic/sampletopic -n "${NAMESPACE}" \
        --for=condition=Ready --timeout=120s

    echo "Strimzi Kafka cluster ready: dapr-kafka-kafka-bootstrap.${NAMESPACE}.svc.cluster.local:9092"

elif [[ "${ACTION}" == "delete" ]]; then
    echo "==> Removing Kafka CRs"
    "${KUBECTL[@]}" delete -n "${NAMESPACE}" -f "${REPO_ROOT}/k8s/strimzi-kafka.yaml" --ignore-not-found=true

    echo "==> Uninstalling Strimzi operator"
    helm "${HELM_CTX[@]}" uninstall "${RELEASE_NAME}" --namespace "${NAMESPACE}" --ignore-not-found || true

    echo "==> Deleting ${NAMESPACE} namespace"
    "${KUBECTL[@]}" delete namespace "${NAMESPACE}" --ignore-not-found=true
fi
