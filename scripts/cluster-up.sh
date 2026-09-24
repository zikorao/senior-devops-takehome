#!/usr/bin/env bash
# Create the local kind cluster, install ingress-nginx, and load app images.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER=takehome
INGRESS_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/kind/deploy.yaml"

if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER" --config "$ROOT/deploy/kind/cluster.yaml"
fi
kubectl config use-context "kind-${CLUSTER}"

if ! kubectl -n ingress-nginx get deployment ingress-nginx-controller >/dev/null 2>&1; then
  kubectl apply -f "$INGRESS_URL"
fi
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=240s

load_image() {
  local image="$1"
  if kind load docker-image "$image" --name "$CLUSTER"; then
    return 0
  fi
  # kind's ctr import rejects some multi-arch indexes. Import the local image directly.
  echo "kind load failed for ${image}; importing with ctr"
  docker save "$image" | docker exec -i "${CLUSTER}-control-plane" ctr --namespace=k8s.io images import -
}

images=(
  devops-takehome-api:local
  devops-takehome-worker:local
  devops-takehome-mock:1.0.0
  rabbitmq:4.1.4-management
  redis:7.4.5-alpine
)
if [[ -n "${IMAGE_TAG:-}" && "${IMAGE_TAG}" != "local" ]]; then
  images+=(
    "devops-takehome-api:${IMAGE_TAG}"
    "devops-takehome-worker:${IMAGE_TAG}"
    "devops-takehome-mock:${IMAGE_TAG}"
  )
fi
for image in "${images[@]}"; do
  load_image "$image"
done

echo "Cluster ${CLUSTER} is ready. Ingress listens on http://127.0.0.1:8080"
