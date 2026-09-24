#!/usr/bin/env bash
# Remove the local kind cluster and the Compose dependency volumes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if kind get clusters | grep -qx takehome; then
  kind delete cluster --name takehome
fi
if [[ -f "$ROOT/compose.dependencies.yaml" ]] && docker compose version >/dev/null 2>&1; then
  docker compose -f "$ROOT/compose.dependencies.yaml" down -v
fi
echo "Removed kind cluster takehome and Compose dependency volumes."
