#!/usr/bin/env bash
# Stop the worker and wait until JobsQueueUnconsumed is firing, then restore it.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
NS=takehome
kubectl config use-context kind-takehome >/dev/null

restore() {
  kubectl -n "$NS" scale deployment/worker --replicas=1 >/dev/null || true
  kubectl -n "$NS" patch cronjob worker-scaler --type merge -p '{"spec":{"suspend":false}}' >/dev/null || true
  kubectl -n "$NS" rollout status deployment/worker --timeout=180s || true
}
trap restore EXIT

alert_state() {
  kubectl -n "$NS" exec deploy/prometheus -- wget -qO- \
    'http://127.0.0.1:9090/api/v1/alerts' \
    | python3 -c 'import json,sys; alerts=json.load(sys.stdin)["data"]["alerts"]; match=[item["state"] for item in alerts if item["labels"].get("alertname")=="JobsQueueUnconsumed"]; print(match[0] if match else "inactive")'
}

echo "== confirm the queue has consumers =="
kubectl -n "$NS" patch cronjob worker-scaler --type merge -p '{"spec":{"suspend":true}}' >/dev/null
kubectl -n "$NS" delete job -l app.kubernetes.io/name=worker-scaler --ignore-not-found >/dev/null
names="$(kubectl -n "$NS" get jobs -o name | grep worker-scaler || true)"
if [[ -n "$names" ]]; then
  kubectl -n "$NS" delete $names >/dev/null
fi
baseline=firing
for _ in $(seq 1 12); do
  baseline="$(alert_state)"
  echo "JobsQueueUnconsumed ${baseline}"
  if [[ "$baseline" != "firing" ]]; then
    break
  fi
  sleep 5
done
if [[ "$baseline" == "firing" ]]; then
  echo "alert was already firing while workers were expected to be up" >&2
  exit 1
fi

echo "== stop workers =="
kubectl -n "$NS" scale deployment/worker --replicas=0 >/dev/null
kubectl -n "$NS" wait --for=delete pod -l app.kubernetes.io/name=worker --timeout=120s

state=inactive
for _ in $(seq 1 24); do
  state="$(alert_state)"
  echo "JobsQueueUnconsumed ${state}"
  if [[ "$state" == "firing" ]]; then
    break
  fi
  sleep 5
done
if [[ "$state" != "firing" ]]; then
  echo "JobsQueueUnconsumed did not fire" >&2
  exit 1
fi

echo "== restore workers =="
restore
trap - EXIT
echo "JobsQueueUnconsumed fired and the worker was restored"
