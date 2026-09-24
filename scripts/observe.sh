#!/usr/bin/env bash
# One health view: pod state, CPU/memory, API and worker metrics, queue depth, and recent logs.
set -euo pipefail

NS=takehome
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kubectl config use-context kind-takehome >/dev/null

echo "== pods =="
kubectl -n "$NS" get pods

if ! kubectl -n "$NS" top pods >/dev/null 2>&1; then
  echo "== installing metrics-server =="
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.0/components.yaml
  kubectl -n kube-system patch deployment metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
  kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
  for _ in $(seq 1 30); do
    if kubectl -n "$NS" top pods >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
fi

echo "== cpu and memory =="
kubectl -n "$NS" top pods

python_metrics='
import urllib.request
text = urllib.request.urlopen("http://127.0.0.1:%s/metrics", timeout=3).read().decode()
for line in text.splitlines():
    if line.startswith("#") or "_bucket" in line:
        continue
    if line.startswith(("api_http_", "worker_")):
        print(line)
'

echo "== api metrics =="
kubectl -n "$NS" exec deploy/api -c api -- python -c "$(printf "$python_metrics" 8000)"

echo "== worker metrics =="
kubectl -n "$NS" exec deploy/worker -c worker -- python -c "$(printf "$python_metrics" 8001)"

echo "== queue depth =="
kubectl -n "$NS" exec deploy/rabbitmq -- rabbitmqctl list_queues name messages messages_ready messages_unacknowledged

echo "== recent worker logs =="
kubectl -n "$NS" logs deploy/worker --tail=15

echo "== recent api logs =="
kubectl -n "$NS" logs deploy/api --tail=10
echo "Observed namespace ${NS}. Base URL for jobs: http://127.0.0.1:8080/jobs"
echo "Manifest directory: ${ROOT}/deploy/kustomize"
