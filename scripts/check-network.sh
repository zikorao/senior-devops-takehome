#!/usr/bin/env bash
# Show whether the installed CNI enforces NetworkPolicy. Creating the objects is not proof.
set -euo pipefail

NS=takehome
kubectl config use-context kind-takehome >/dev/null
kubectl apply -k "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/deploy/kustomize" >/dev/null
# kindnet programs policies shortly after they are created.
sleep 8

echo "== NetworkPolicy objects =="
kubectl -n "$NS" get networkpolicy

echo "== CNI pods =="
kubectl -n kube-system get pods -o name | grep -E 'kindnet|calico|cilium|aws-node|antrea' || true

kubectl -n "$NS" delete pod netcheck --ignore-not-found --wait=true >/dev/null
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: netcheck
  namespace: takehome
  labels:
    app.kubernetes.io/name: netcheck
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  containers:
    - name: netcheck
      image: devops-takehome-api:local
      imagePullPolicy: IfNotPresent
      command:
        - python
        - -c
        - |
          import socket
          socket.create_connection(("redis.takehome.svc.cluster.local", 6379), 5).close()
          print("REDIS_REACHABLE")
EOF

phase=""
for _ in $(seq 1 30); do
  phase="$(kubectl -n "$NS" get pod netcheck -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]]; then
    break
  fi
  sleep 1
done

echo "== netcheck phase: ${phase:-unknown} =="
kubectl -n "$NS" logs pod/netcheck || true
if [[ "$phase" == "Succeeded" ]]; then
  echo "ENFORCEMENT: no. An unlabeled pod reached Redis, so this CNI is not applying NetworkPolicy."
elif [[ "$phase" == "Failed" ]]; then
  echo "ENFORCEMENT: yes. The unlabeled pod could not reach Redis."
else
  echo "ENFORCEMENT: unknown. netcheck did not finish."
  exit 1
fi
kubectl -n "$NS" delete pod netcheck --wait=false >/dev/null
