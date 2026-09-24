#!/usr/bin/env bash
# Create the kind cluster from deploy/kind/cluster.yaml when it does not exist.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

: "${CLUSTER_NAME:?}"
: "${CLUSTER_CONFIG:?}"

if ! kind get clusters | grep -qx "$CLUSTER_NAME"; then
  kind create cluster --name "$CLUSTER_NAME" --config "$CLUSTER_CONFIG"
fi

kubectl config use-context "kind-${CLUSTER_NAME}"
kubectl --context "kind-${CLUSTER_NAME}" cluster-info >/dev/null
echo "Cluster ${CLUSTER_NAME} is ready."
