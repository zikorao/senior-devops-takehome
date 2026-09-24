#!/usr/bin/env bash
# Restart the worker, then scale it to two replicas. Jobs must still complete.
set -euo pipefail

NS=takehome
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE=("$ROOT/.venv/bin/python" "$ROOT/scripts/smoke_test.py" --base-url "${API_BASE_URL:-http://127.0.0.1:8080}")
kubectl config use-context kind-takehome >/dev/null

echo "== restart worker =="
kubectl -n "$NS" delete pod -l app.kubernetes.io/name=worker --wait=true
kubectl -n "$NS" rollout status deployment/worker --timeout=180s
"${SMOKE[@]}"

echo "== scale worker to 2 =="
kubectl -n "$NS" scale deployment/worker --replicas=2
kubectl -n "$NS" rollout status deployment/worker --timeout=180s
kubectl -n "$NS" get pods -l app.kubernetes.io/name=worker
"${SMOKE[@]}"

echo "== restore worker replicas to 1 =="
kubectl -n "$NS" scale deployment/worker --replicas=1
kubectl -n "$NS" rollout status deployment/worker --timeout=180s
echo "Worker restart and scale completed with jobs succeeding."
