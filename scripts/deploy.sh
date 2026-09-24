#!/usr/bin/env bash
# Apply the takehome namespace. Generates credentials once and never prints them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS=takehome
CLUSTER=takehome

kubectl config use-context "kind-${CLUSTER}"
kubectl apply -f "$ROOT/deploy/kustomize/namespace.yaml"

if ! kubectl -n "$NS" get secret app-credentials >/dev/null 2>&1; then
  rabbit_password="$(openssl rand -hex 16)"
  redis_password="$(openssl rand -hex 16)"
  kubectl -n "$NS" create secret generic app-credentials \
    --from-literal=RABBITMQ_USER=takehome \
    --from-literal=RABBITMQ_PASSWORD="$rabbit_password" \
    --from-literal=REDIS_PASSWORD="$redis_password" \
    --from-literal=RABBITMQ_URL="amqp://takehome:${rabbit_password}@rabbitmq:5672/" \
    --from-literal=REDIS_URL="redis://:${redis_password}@redis:6379/0"
fi

manifests="$ROOT/deploy/kustomize"
if [[ -n "${IMAGE_TAG:-}" && "${IMAGE_TAG}" != "local" ]]; then
  manifests="$(mktemp -d)"
  cp -R "$ROOT/deploy/kustomize/." "$manifests/"
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
  trap 'rm -rf "$manifests"' EXIT
fi

kubectl apply -k "$manifests"

for deploy in redis rabbitmq mock api worker; do
  kubectl -n "$NS" rollout status "deployment/${deploy}" --timeout=240s
done

echo "Deployed namespace ${NS}. Job API: http://127.0.0.1:8080/jobs"
