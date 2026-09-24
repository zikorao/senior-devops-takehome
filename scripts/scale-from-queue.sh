#!/usr/bin/env bash
# Pause the worker, queue four jobs, and let the scaler choose the replica count.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
NS=takehome
API="${API_BASE_URL:-http://127.0.0.1:8080}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kubectl config use-context kind-takehome >/dev/null

restore() {
  kubectl -n "$NS" scale deployment/worker --replicas=1 >/dev/null || true
  kubectl -n "$NS" patch cronjob worker-scaler --type merge -p '{"spec":{"suspend":false}}' >/dev/null || true
  kubectl -n "$NS" rollout status deployment/worker --timeout=180s || true
}
trap restore EXIT

queue_depth() {
  kubectl -n "$NS" exec deploy/prometheus -- wget -qO- \
    'http://127.0.0.1:9090/api/v1/query?query=sum(rabbitmq_queue_messages%7Bqueue=%22jobs%22%7D)' \
    | python3 -c 'import json,sys; body=json.load(sys.stdin); result=body["data"]["result"]; print(result[0]["value"][1] if result else 0)'
}

run_scaler() {
  local job="queue-scale-$1"
  kubectl -n "$NS" delete job "$job" --ignore-not-found >/dev/null
  kubectl -n "$NS" create job "$job" --from=cronjob/worker-scaler >/dev/null
  if ! kubectl -n "$NS" wait --for=condition=complete "job/${job}" --timeout=90s; then
    kubectl -n "$NS" logs "job/${job}" || true
    exit 1
  fi
  kubectl -n "$NS" logs "job/${job}"
}

echo "== suspend scaler and stop workers =="
kubectl -n "$NS" patch cronjob worker-scaler --type merge -p '{"spec":{"suspend":true}}' >/dev/null
kubectl -n "$NS" delete job -l app.kubernetes.io/name=worker-scaler --ignore-not-found >/dev/null
names="$(kubectl -n "$NS" get jobs -o name | grep worker-scaler || true)"
if [[ -n "$names" ]]; then
  # names are job/worker-scaler-* with no spaces
  kubectl -n "$NS" delete $names >/dev/null
fi
kubectl -n "$NS" scale deployment/worker --replicas=0 >/dev/null
kubectl -n "$NS" wait --for=delete pod -l app.kubernetes.io/name=worker --timeout=120s

echo "== queue four jobs =="
for n in 1 2 3 4; do
  curl -fsS -H 'Content-Type: application/json' -d "{\"prompt\":\"scale ${n}\"}" "${API}/jobs" >/dev/null
done
depth=0
for _ in $(seq 1 20); do
  depth="$(queue_depth)"
  if python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) >= 4 else 1)" "$depth"; then
    break
  fi
  sleep 2
done
echo "queue depth ${depth}"
if ! python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) >= 4 else 1)" "$depth"; then
  echo "queue did not reach 4 messages" >&2
  exit 1
fi

echo "== scale up =="
run_scaler up
replicas="$(kubectl -n "$NS" get deploy worker -o jsonpath='{.spec.replicas}')"
if [[ "$replicas" != "3" ]]; then
  echo "expected 3 replicas, got ${replicas}" >&2
  exit 1
fi
kubectl -n "$NS" rollout status deployment/worker --timeout=180s
echo "worker replicas ${replicas}"

echo "== drain and scale down =="
depth=1
for _ in $(seq 1 45); do
  depth="$(queue_depth)"
  if python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) == 0 else 1)" "$depth"; then
    break
  fi
  sleep 2
done
echo "queue depth after drain ${depth}"
run_scaler down
replicas="$(kubectl -n "$NS" get deploy worker -o jsonpath='{.spec.replicas}')"
if [[ "$replicas" != "1" ]]; then
  echo "expected 1 replica, got ${replicas}" >&2
  exit 1
fi
echo "worker replicas ${replicas}"
trap - EXIT
kubectl -n "$NS" patch cronjob worker-scaler --type merge -p '{"spec":{"suspend":false}}' >/dev/null
"$ROOT/.venv/bin/python" "$ROOT/scripts/smoke_test.py" --base-url "$API"
