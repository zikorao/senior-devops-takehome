#!/usr/bin/env bash
# Start a local registry on 127.0.0.1:5001 when a remote DOCKER_REGISTRY is not set.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

name=takehome-registry
if docker container inspect "$name" >/dev/null 2>&1; then
  docker start "$name" >/dev/null
else
  docker run -d --name "$name" --restart unless-stopped -p 127.0.0.1:5001:5000 registry:2 >/dev/null
fi

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:5001/v2/ >/dev/null; then
    echo "Registry ready at localhost:5001"
    exit 0
  fi
  sleep 1
done
echo "Registry did not become ready on 127.0.0.1:5001" >&2
exit 1
