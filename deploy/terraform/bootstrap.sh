#!/usr/bin/env bash
# Install ingress, load images, generate credentials once, and apply Kustomize.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

: "${CLUSTER_NAME:?}"
: "${IMAGE_TAG:?}"
: "${REPO_ROOT:?}"
: "${RABBITMQ_PASSWORD:?}"
: "${REDIS_PASSWORD:?}"

NS=takehome
INGRESS_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/kind/deploy.yaml"

kubectl config use-context "kind-${CLUSTER_NAME}"

kubectl apply -f "$INGRESS_URL"
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=240s

load_image() {
  local image="$1"
  if kind load docker-image "$image" --name "$CLUSTER_NAME"; then
    return 0
  fi
  echo "kind load failed for ${image}; importing with ctr"
  docker save "$image" | docker exec -i "${CLUSTER_NAME}-control-plane" ctr --namespace=k8s.io images import -
}

require_image() {
  local image="$1"
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    echo "Missing local image ${image}. Build the app images before apply." >&2
    exit 1
  fi
  load_image "$image"
}

pull_and_load() {
  local image="$1"
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    docker pull "$image"
  fi
  load_image "$image"
}

require_image devops-takehome-api:local
require_image devops-takehome-worker:local
require_image devops-takehome-mock:1.0.0
pull_and_load rabbitmq:4.1.4-management
pull_and_load redis:7.4.5-alpine
pull_and_load prom/prometheus:v3.5.0
pull_and_load grafana/grafana:12.1.1

if [[ "$IMAGE_TAG" != "local" ]]; then
  require_image "devops-takehome-api:${IMAGE_TAG}"
  require_image "devops-takehome-worker:${IMAGE_TAG}"
  require_image "devops-takehome-mock:${IMAGE_TAG}"
fi

kubectl apply -f "$REPO_ROOT/deploy/kustomize/namespace.yaml"

# Leave an existing Secret alone so apply does not rotate passwords under running pods.
# A new cluster has no Secret, so the Terraform-generated values are used.
if ! kubectl -n "$NS" get secret app-credentials >/dev/null 2>&1; then
  kubectl -n "$NS" create secret generic app-credentials \
    --from-literal=RABBITMQ_USER=takehome \
    --from-literal=RABBITMQ_PASSWORD="$RABBITMQ_PASSWORD" \
    --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
    --from-literal=RABBITMQ_URL="amqp://takehome:${RABBITMQ_PASSWORD}@rabbitmq:5672/" \
    --from-literal=REDIS_URL="redis://:${REDIS_PASSWORD}@redis:6379/0" \
    >/dev/null
fi

manifests="$REPO_ROOT/deploy/kustomize"
if [[ "$IMAGE_TAG" != "local" ]]; then
  manifests="$(mktemp -d)"
  trap 'rm -rf "$manifests"' EXIT
  cp -R "$REPO_ROOT/deploy/kustomize/." "$manifests/"
  IMAGE_TAG="$IMAGE_TAG" MANIFESTS="$manifests" python3 - <<'PY'
import os
from pathlib import Path

root = Path(os.environ["MANIFESTS"])
tag = os.environ["IMAGE_TAG"]
replacements = {
    "devops-takehome-api:local": f"devops-takehome-api:{tag}",
    "devops-takehome-worker:local": f"devops-takehome-worker:{tag}",
    "devops-takehome-mock:1.0.0": f"devops-takehome-mock:{tag}",
}
for path in root.rglob("*.yaml"):
    text = path.read_text()
    for old, new in replacements.items():
        text = text.replace(old, new)
    path.write_text(text)
PY
fi

kubectl apply -k "$manifests"

for deploy in redis rabbitmq mock api worker prometheus grafana; do
  kubectl -n "$NS" rollout status "deployment/${deploy}" --timeout=240s
done

echo "Deployed namespace ${NS}. Job API: http://127.0.0.1:8080/jobs"
