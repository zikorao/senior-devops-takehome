#!/usr/bin/env bash
# Put the mock in unavailable mode, confirm the job fails, then restore it.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
NS=takehome
API="${API_BASE_URL:-http://127.0.0.1:8080}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kubectl config use-context kind-takehome >/dev/null

restore() {
  kubectl -n "$NS" patch configmap app-config --type merge -p '{"data":{"MOCK_MODE":"normal"}}' >/dev/null
  kubectl -n "$NS" rollout restart deployment/mock >/dev/null
  kubectl -n "$NS" rollout status deployment/mock --timeout=180s
}
trap restore EXIT

echo "== mock unavailable =="
kubectl -n "$NS" patch configmap app-config --type merge -p '{"data":{"MOCK_MODE":"unavailable"}}' >/dev/null
kubectl -n "$NS" rollout restart deployment/mock >/dev/null
kubectl -n "$NS" rollout status deployment/mock --timeout=180s
livez="$(kubectl -n "$NS" exec deploy/mock -- python -c 'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:8081/livez").read().decode())')"
echo "mock livez: ${livez}"
printf '%s' "$livez" | python3 -c 'import json,sys; body=json.load(sys.stdin); assert body["status"]=="ready" and body["mode"]=="unavailable"'

job_id="$(curl -fsS -H 'Content-Type: application/json' -d '{"prompt":"dependency failure"}' "${API}/jobs" | python3 -c 'import json,sys; print(json.load(sys.stdin)["job_id"])')"
echo "submitted ${job_id}"
error=""
for _ in $(seq 1 40); do
  body="$(curl -fsS "${API}/jobs/${job_id}")"
  status="$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
  if [[ "$status" == "failed" ]]; then
    error="$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error") or "")')"
    break
  fi
  sleep 1
done
if [[ "$error" != "external_unavailable" ]]; then
  echo "job ${job_id} ended as '${error:-$status}'" >&2
  exit 1
fi
echo "job ${job_id} failed with external_unavailable"

echo "== restore mock =="
restore
trap - EXIT
"$ROOT/.venv/bin/python" "$ROOT/scripts/smoke_test.py" --base-url "$API"
