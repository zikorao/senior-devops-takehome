#!/usr/bin/env bash
# A bad API image must fail the rollout. Undo restores the previous image.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
NS=takehome
API="${API_BASE_URL:-http://127.0.0.1:8080}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kubectl config use-context kind-takehome >/dev/null

current="$(kubectl -n "$NS" get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}')"
restore() {
  kubectl -n "$NS" set image "deployment/api" "api=${current}" >/dev/null
  kubectl -n "$NS" rollout status deployment/api --timeout=180s
}
trap restore EXIT

echo "== bad image ${current} -> devops-takehome-api:does-not-exist =="
kubectl -n "$NS" set image deployment/api api=devops-takehome-api:does-not-exist >/dev/null
if kubectl -n "$NS" rollout status deployment/api --timeout=45s; then
  echo "bad image rollout succeeded" >&2
  exit 1
fi
echo "bad image rollout failed"

echo "== undo =="
kubectl -n "$NS" rollout undo deployment/api >/dev/null
kubectl -n "$NS" rollout status deployment/api --timeout=180s
restored="$(kubectl -n "$NS" get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}')"
if [[ "$restored" != "$current" ]]; then
  echo "undo restored '${restored}', expected '${current}'" >&2
  exit 1
fi
trap - EXIT
"$ROOT/.venv/bin/python" "$ROOT/scripts/smoke_test.py" --base-url "$API"
echo "Rollback restored ${restored}"
