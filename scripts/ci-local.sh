#!/usr/bin/env bash
# Local equivalent of Jenkinsfile. Exits non-zero when tests, rollout, or smoke fail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short=12 HEAD)}"
export IMAGE_TAG
API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:8080}"

python_bin() {
  if command -v python3.12 >/dev/null 2>&1; then
    command -v python3.12
  else
    command -v python3
  fi
}

stage_test() {
  local py
  py="$(python_bin)"
  "$py" -m venv "$ROOT/.venv"
  "$ROOT/.venv/bin/python" -m pip install --require-hashes -r "$ROOT/requirements-dev.lock"
  "$ROOT/.venv/bin/python" -m pytest -m 'not integration' -q
  "$ROOT/.venv/bin/python" "$ROOT/scripts/init_env.py"
  docker compose -f "$ROOT/compose.dependencies.yaml" up -d --build --wait
  local status=0
  RUN_INTEGRATION=1 "$ROOT/.venv/bin/python" -m pytest -m integration -q || status=$?
  docker compose -f "$ROOT/compose.dependencies.yaml" down -v
  return "$status"
}

stage_build() {
  docker build -f "$ROOT/deploy/docker/api.Dockerfile" \
    -t "devops-takehome-api:${IMAGE_TAG}" -t devops-takehome-api:local "$ROOT"
  docker build -f "$ROOT/deploy/docker/worker.Dockerfile" \
    -t "devops-takehome-worker:${IMAGE_TAG}" -t devops-takehome-worker:local "$ROOT"
  docker build -f "$ROOT/mock/Dockerfile" \
    -t "devops-takehome-mock:${IMAGE_TAG}" -t devops-takehome-mock:1.0.0 "$ROOT"
  echo "Immutable image tag ${IMAGE_TAG}"
}

stage_push() {
  local name
  for name in devops-takehome-api devops-takehome-worker devops-takehome-mock; do
    docker image inspect "${name}:${IMAGE_TAG}" >/dev/null
  done
  if [[ -n "${DOCKER_REGISTRY:-}" ]]; then
    for name in devops-takehome-api devops-takehome-worker devops-takehome-mock; do
      docker tag "${name}:${IMAGE_TAG}" "${DOCKER_REGISTRY}/${name}:${IMAGE_TAG}"
      docker push "${DOCKER_REGISTRY}/${name}:${IMAGE_TAG}"
    done
    echo "Pushed ${IMAGE_TAG} to ${DOCKER_REGISTRY}"
    return 0
  fi
  echo "DOCKER_REGISTRY is unset. Deploy will load ${IMAGE_TAG} into the kind node."
  echo "Jenkins uses credential docker-registry to docker login before this stage."
}

stage_deploy() {
  "$ROOT/scripts/cluster-up.sh"
  "$ROOT/scripts/deploy.sh"
}

stage_smoke() {
  "$ROOT/.venv/bin/python" "$ROOT/scripts/smoke_test.py" --base-url "$API_BASE_URL"
}

usage() {
  echo "usage: $0 {test|build|push|deploy|smoke|all}" >&2
  return 2
}

cmd="${1:-all}"
case "$cmd" in
  test) stage_test ;;
  build) stage_build ;;
  push) stage_push ;;
  deploy) stage_deploy ;;
  smoke) stage_smoke ;;
  all)
    stage_test
    stage_build
    stage_push
    stage_deploy
    stage_smoke
    ;;
  *) usage ;;
esac
