# DevOps take-home application

Start with [ASSIGNMENT.md](ASSIGNMENT.md). This starter supplies a working application;
your task is its containerization, Kubernetes deployment, and operational tooling.
Stop after four hours and describe unfinished work. An optional cloud deployment
does not earn extra credit.

## Prerequisites

- Python **3.12** (tested with 3.12.11), a container runtime with Docker Compose support,
  and Git. Docker Desktop, or an equivalent supported runtime, is sufficient.
- For your solution: a local Kubernetes distribution, kubectl, and your chosen
  deployment tooling. No cloud or AI-provider account is necessary.
- Internet access is needed initially to download dependencies and images. Running
  the application needs no internet service.
- macOS/Linux or Windows through WSL2; AMD64 and ARM64 are intended targets.
  Start with 4 CPUs and 8 GiB allocated to your runtime; this is a planning budget,
  not a measured minimum. Adjust your monitoring footprint to your laptop.

## First run (application development only)

From the extracted directory:

```sh
git init
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install --require-hashes -r requirements-dev.lock
python scripts/init_env.py
docker compose -f compose.dependencies.yaml up -d --build --wait
python -m pytest -m 'not integration' -q
RUN_INTEGRATION=1 python -m pytest -m integration -q
```

In two terminals, activate the environment, stay in this directory, and run:

```sh
python -m takehome api
```

```sh
python -m takehome worker
```

In a third terminal:

```sh
python scripts/smoke_test.py --base-url http://127.0.0.1:8000
python scripts/load_test.py --base-url http://127.0.0.1:8000 --jobs 30 --concurrency 5
```

The Compose file runs **only dependencies**. It is a quick way to establish that
the supplied code works before building your own application containers and
Kubernetes deployment. It is not an assignment solution. The mock Dockerfile is
provided; author the API and worker Dockerfiles yourself.

The programs automatically read the ignored `.env` file. `init_env.py` creates
random local passwords with restrictive file permissions and never overwrites an
existing file. Do not use the placeholder values in `.env.example`.

The development API is at port 8000; worker operations at 8001; mock at 8081;
RabbitMQ AMQP at 5672, RabbitMQ management at 15672; Redis at 6379. Compose publishes
dependency ports only on loopback. Keep these dependencies internal in Kubernetes.
Read local management credentials from your `.env`; do not include them in your submission.

## Architecture and operational contract

```text
Client -> Ingress -> API -> RabbitMQ -> Worker -> Mock HTTP service
                     |                   |
                     +----> Redis <------+
```

The API writes initial state and reads results in Redis. The mock represents an
external service but is bundled and deployed internally for this exercise. Explain
real external DNS/egress controls in your README; internet egress is not required
for the local mock.

See [APPLICATION.md](APPLICATION.md) for endpoints, environment configuration,
metrics, delivery behavior, and known limitations. Unit tests do not need running
dependencies. Integration tests use a unique queue, start the API/worker in-process,
and require the real Compose dependencies. Run them in the mock's normal mode.

## Mock controls

```sh
MOCK_MODE=unavailable docker compose -f compose.dependencies.yaml up -d --no-deps mock
# New jobs should reach failed after bounded retries.
MOCK_MODE=slow MOCK_DELAY_SECONDS=8 docker compose -f compose.dependencies.yaml up -d --no-deps mock
# Default HTTP timeout is 5 seconds; slower responses exercise timeouts.
MOCK_MODE=normal docker compose -f compose.dependencies.yaml up -d --no-deps mock
```

For optional prebuilt archives, download the archive matching your runtime's Linux
architecture and verify it against the provided SHA-256 manifest:

```sh
docker load -i devops-takehome-mock-v1.0.0-arm64.tar.gz
docker compose -f compose.dependencies.yaml up -d --no-build --wait
```

Use the `amd64` archive on an AMD64 runtime. Both archives load the same local tag,
`devops-takehome-mock:1.0.0`; do not load both into the same image store. You can
always build `mock/Dockerfile` from this directory instead.

## Cleanup

Stop the two Python processes with Ctrl-C. This removes local dependency containers
and their exercise data volumes:

```sh
docker compose -f compose.dependencies.yaml down -v
```

You are responsible for documenting cleanup of your own deployment. See the
submission checklist in the assignment before handing in your repository.

## CI/CD

`Jenkinsfile` is the pipeline: checkout, tests, image build, immutable git-SHA tag, push, deploy, and smoke. `.github/workflows/ci.yml` runs the same `scripts/ci-local.sh` on GitHub-hosted runners. That workflow is the executed CI for this repository. A Jenkins run was not claimed.

The script exits non-zero when unit or integration tests fail, a rollout does not become ready, or `scripts/smoke_test.py` fails. With `DOCKER_REGISTRY` unset, the push stage records the immutable tag and the deploy stage loads it into the kind node. A Jenkins agent that should push to a remote registry sets `DOCKER_REGISTRY` and logs in with credential id `docker-registry`.

The agent needs Git, Python 3.12, Docker with Compose, kind, kubectl, openssl, and network access to pull base images. It also needs a Docker socket and permission to create a local kind cluster. No cloud credentials are required.

## Operations

```text
Client :8080 -> ingress-nginx /jobs
             -> api:8000 (2 replicas) -> rabbitmq:5672 -> worker:8001 -> mock:8081/infer
                       |                        |
                       +-------- redis:6379 -----+
```

Bring the cluster up with `scripts/cluster-up.sh`, then `scripts/deploy.sh`. Remove it with `scripts/cleanup.sh`. Job traffic is `http://127.0.0.1:8080/jobs`. RabbitMQ, Redis, the mock, the worker, and `/livez`, `/readyz`, and `/metrics` stay on ClusterIP. Ingress checks on 24 Sep 2026 returned nginx 404 for those operational paths and the API JSON body `{"detail":"job not found"}` for an unknown job id.

Liveness is `/livez`. Readiness is `/readyz`. Startup uses `/livez`, so a slow broker does not crash the process. `terminationGracePeriodSeconds` is 30, above the worker's 20-second drain. API and worker set `enableServiceLinks: false`. API starts at 2 replicas with `maxUnavailable: 0`. The worker starts at 1. Redis and RabbitMQ are single-replica Deployments with `emptyDir` and Redis AOF. That survives a container restart only while the pod stays on the node. It is not a backup or a highly available broker.

### Networking and security

`deploy/kustomize/networkpolicy.yaml` is default-deny plus allows: ingress-nginx to the API, the API and worker to RabbitMQ and Redis, and the worker to the mock. DNS egress to `kube-system` is included so the same rules can work on an enforcing CNI. kind's CNI is kindnet. `scripts/check-network.sh` applied the policies and a pod labeled `netcheck` still opened TCP to Redis (`REDIS_REACHABLE`, phase Succeeded). The objects exist and are not enforced here. An enforcing CNI such as Calico or Cilium would make that connection fail. Kubelet probes are node traffic; on an enforcing CNI, confirm probes still reach `/livez` before relying on the policies.

Credentials are generated into the `app-credentials` Secret by `scripts/deploy.sh` and are not stored in git. `secret.example.yaml` shows the key names only. Application containers run as uid 10001 with a read-only root filesystem. Redis runs as uid 999. The RabbitMQ image starts as root so it can drop to the `rabbitmq` user. The API is unauthenticated. A production ingress would terminate TLS, require authentication, and restrict source networks. A real inference provider would be reached through an allow-listed egress proxy, with an idempotency key, because delivery is at least once.

### Observability

`scripts/observe.sh` installs metrics-server on first use (kind needs `--kubelet-insecure-tls`) and prints pod state, `kubectl top pods`, API and worker Prometheus series, `rabbitmqctl list_queues`, and recent JSON logs. A local run showed both API replicas and the worker under 50Mi, RabbitMQ at 129m CPU and 93Mi, `worker_consumer_connected 1`, `worker_jobs_in_progress 0`, and queue `jobs` at 0 ready and 0 unacknowledged. Worker logs for job `f021a396-741b-4d45-92f6-92f3d8d0943c` were `job_started` then `job_finished` with `status=succeeded`. Counters reset on process restart; use rates. API latency is handler time, not queue-to-result time. Queue age, not CPU, is the useful worker scale signal.

### Resilience

`scripts/resilience.sh` deleted the worker pod, waited for the replacement, and the smoke test passed (`e8c9b1ba-9978-4afe-8e06-2ef5a519623b`). It then scaled the worker to 2 replicas and the smoke test passed again (`e0ae037d-85b4-4133-970d-cdc8dbc03a69`). The script scales back to 1 so the cluster matches the manifest. Retries on transport errors, HTTP 429, and 5xx stop at `EXTERNAL_MAX_ATTEMPTS` (3). `MOCK_MODE=unavailable` ends new jobs as `failed` / `external_unavailable` while mock `/livez` stays 200. A bad image tag fails `kubectl rollout status`, which fails `scripts/deploy.sh` and the pipeline. Rollback of a pushed SHA is `kubectl rollout undo deployment/api -n takehome`.

### Time

Timed implementation on 24 Sep 2026 was about 45 minutes, from the API and worker images through this note (roughly 13:25–14:05 America/Toronto). Tool installs and the first Compose test were before that clock. Work stopped under the four-hour cap.

Completed: API and worker images, kind deploy, ingress limited to `/jobs`, GitHub Actions pipeline (Jenkinsfile is the same script), observability, worker restart and scale, and a kindnet check showing NetworkPolicy is not enforced.

Next, if more time were available: an enforcing CNI, queue-based worker scaling, and durable Redis and RabbitMQ.

### Production follow-ups

API CPU autoscaling would track the wrong signal for this I/O-bound service. Scale workers from queue depth or age. Redis and RabbitMQ need replicated disks, backups, and a restore drill before they are highly available. Publish and the Redis write are not one transaction, and a crash after the mock call can repeat work. Terminal state expires with `RESULT_TTL_SECONDS`. Malformed messages are dropped with no dead-letter queue. Those stay application limits; this deployment does not change them.
