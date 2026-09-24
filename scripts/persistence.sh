#!/usr/bin/env bash
# Show Redis and RabbitMQ data surviving a pod delete. The volume is on the kind node.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
NS=takehome
kubectl config use-context kind-takehome >/dev/null

echo "== redis survives pod delete =="
kubectl -n "$NS" exec deploy/redis -- sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli set takehome:persist ok' >/dev/null
kubectl -n "$NS" delete pod -l app.kubernetes.io/name=redis --wait=true
kubectl -n "$NS" rollout status deployment/redis --timeout=180s
redis_value="$(kubectl -n "$NS" exec deploy/redis -- sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli get takehome:persist')"
if [[ "$redis_value" != "ok" ]]; then
  echo "Redis value was '${redis_value}'" >&2
  exit 1
fi
echo "Redis key takehome:persist is still ok"

echo "== rabbitmq survives pod delete =="
kubectl -n "$NS" exec deploy/rabbitmq -- sh -c 'echo ok > /var/lib/rabbitmq/persist-check'
kubectl -n "$NS" delete pod -l app.kubernetes.io/name=rabbitmq --wait=true
kubectl -n "$NS" rollout status deployment/rabbitmq --timeout=240s
rabbit_value="$(kubectl -n "$NS" exec deploy/rabbitmq -- cat /var/lib/rabbitmq/persist-check)"
if [[ "$rabbit_value" != "ok" ]]; then
  echo "RabbitMQ marker was '${rabbit_value}'" >&2
  exit 1
fi
echo "RabbitMQ marker is still ok"
