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

The script exits non-zero when unit or integration tests fail, a rollout does not become ready, or `scripts/smoke_test.py` fails. With `DOCKER_REGISTRY` unset, the push stage starts a registry on `127.0.0.1:5001` and pushes the immutable tag there. The deploy stage still loads that image into the kind node, because the node is not configured as a registry mirror. A Jenkins agent that should push to a remote registry sets `DOCKER_REGISTRY` and logs in with credential id `docker-registry`.

The agent needs Git, Python 3.12, Docker with Compose, Terraform 1.5 or newer, kind, kubectl, and network access to pull base images. It also needs a Docker socket and permission to create a local kind cluster. No cloud credentials are required.

## Operations

```text
Client :8080 -> ingress-nginx /jobs
             -> api:8000 (2 replicas) -> rabbitmq:5672 -> worker:8001 -> mock:8081/infer
                       |                        |
                       +-------- redis:6379 -----+
```

Recreate and remove the cluster with Terraform. `scripts/cluster-up.sh` and `scripts/deploy.sh` both apply it, and `scripts/cleanup.sh` destroys it. Job traffic is `http://127.0.0.1:8080/jobs`. RabbitMQ, Redis, the mock, the worker, and `/livez`, `/readyz`, and `/metrics` stay on ClusterIP. Ingress checks on 24 Sep 2026 returned nginx 404 for those operational paths and the API JSON body `{"detail":"job not found"}` for an unknown job id.

Liveness is `/livez`. Readiness is `/readyz`. Startup uses `/livez`, so a slow broker does not crash the process. `terminationGracePeriodSeconds` is 30, above the worker's 20-second drain. API and worker set `enableServiceLinks: false`. API starts at 2 replicas with `maxUnavailable: 0`. The worker starts at 1. Redis and RabbitMQ are single-replica Deployments with a hostPath volume on the kind node, and Redis keeps AOF. `scripts/persistence.sh` deleted each pod and read the same marker back. That survives a pod delete. Deleting the kind node deletes the disk. It is not a backup or a second replica. RabbitMQ uses a fixed node name, `rabbit@rabbitmq`, so the data directory is the same after the pod name changes.

### Networking and security

`deploy/kustomize/networkpolicy.yaml` is default-deny plus allows: ingress-nginx and Prometheus to the API, the API and worker to RabbitMQ and Redis, the worker to the mock, and Prometheus to the metrics ports. DNS egress to `kube-system` is included. kind's CNI is kindnet, and on this cluster it enforces the policies after a short delay. `scripts/check-network.sh` waits, then starts a pod labeled `netcheck`. That pod timed out connecting to Redis, while the API, which is allowed, still can. Kubelet probes are node traffic and the smoke test still passes through ingress.

Credentials are generated into the `app-credentials` Secret by Terraform the first time the namespace is empty. The values stay in local Terraform state and are not stored in git. `secret.example.yaml` shows the key names only. An existing Secret is left unchanged so a later apply does not rotate passwords under running pods. Application containers run as uid 10001 with a read-only root filesystem. Redis runs as uid 999. The RabbitMQ image starts as root so it can drop to the `rabbitmq` user. The API is unauthenticated. A production ingress would terminate TLS, require authentication, and restrict source networks. A real inference provider would be reached through an allow-listed egress proxy, with an idempotency key, because delivery is at least once.

### Observability

`scripts/observe.sh` is the command-line health view. It installs metrics-server on first use (kind needs `--kubelet-insecure-tls`) and prints pod state, `kubectl top pods`, API and worker series, `rabbitmqctl list_queues`, and recent JSON logs. A local run showed both API replicas and the worker under 50Mi, RabbitMQ at 129m CPU and 93Mi, `worker_consumer_connected 1`, `worker_jobs_in_progress 0`, and queue `jobs` at 0 ready and 0 unacknowledged. Worker logs for job `f021a396-741b-4d45-92f6-92f3d8d0943c` were `job_started` then `job_finished` with `status=succeeded`.

Prometheus and Grafana are internal. They are not on the ingress. Prometheus scrapes each API and worker pod at `/metrics` and RabbitMQ’s Prometheus plugin on port 15692, so both API replicas are included. Grafana provisions a Prometheus datasource and the Takehome jobs dashboard: request rate, 5xx ratio, handler-latency p95, worker completions, consumer connection, jobs in progress, and queue depth. Anonymous view access is enabled for this local exercise.

```sh
kubectl -n takehome port-forward svc/grafana 3000:3000
```

Open `http://127.0.0.1:3000` and the dashboard Takehome / Takehome jobs. The dashboard includes firing alert count. RabbitMQ exports per-queue series (`prometheus.return_per_object_metrics`). This image does not export queue age, so depth is the queue signal. CPU and memory stay on `kubectl top` in `scripts/observe.sh`. Logs stay on `kubectl logs`. Counters reset on process restart; the dashboard uses `rate`. API latency is handler time, not queue-to-result time.

Prometheus evaluates four rules: `JobsQueueUnconsumed` (no consumers for 45s), `WorkerConsumerDisconnected`, `ApiErrorRatioHigh`, and `JobsQueueBacklog`. Alertmanager is internal and has no external receiver. `scripts/alert-check.sh` stopped the worker and `JobsQueueUnconsumed` fired, then the worker was restored. kindnet matches API-server traffic after DNAT, on endpoint port 6443, so Prometheus and the scaler are allowed that port.

### Resilience

`scripts/resilience.sh` deleted the worker pod, waited for the replacement, and the smoke test passed (`e8c9b1ba-9978-4afe-8e06-2ef5a519623b`). It then scaled the worker to 2 replicas and the smoke test passed again (`e0ae037d-85b4-4133-970d-cdc8dbc03a69`). The script scales back to 1 so the cluster matches the manifest. Retries on transport errors, HTTP 429, and 5xx stop at `EXTERNAL_MAX_ATTEMPTS` (3).

`scripts/dependency-failure.sh` set `MOCK_MODE=unavailable` and restarted the mock. `/livez` stayed ready. Job `3097c7a7-5cd9-4463-887c-95f7e585bc1a` failed with `external_unavailable`. The script restored `normal`, and the smoke test passed (`aad1a678-4655-40a5-9c62-efe8cf0465f7`).

`scripts/rollback.sh` set the API image to `devops-takehome-api:does-not-exist`. The rollout timed out. `kubectl rollout undo` restored `devops-takehome-api:local`, and the smoke test passed (`4ba7ce77-bc60-4c39-9769-460e5a74a8f5`). A bad image tag also fails `kubectl rollout status`, which fails `scripts/deploy.sh` and the pipeline.

`scripts/scale-from-queue.sh` stopped the worker, queued 4 jobs, and the scaler set 3 replicas. After the queue drained it set 1 replica. The smoke test passed (`f094d44c-0373-4687-9873-97c00c8a3b76`). The CronJob runs every minute: 1 replica below 2 messages, 2 replicas at 2 or 3, and 3 at 4 or more. Apply sets the baseline back to 1. The scaler does not scale to zero.

### Reproducibility

Terraform in `deploy/terraform` recreates and removes the local environment. `deploy/kind/cluster.yaml` is the cluster spec. `deploy/kustomize` is the namespace. Apply creates the kind cluster when it is missing, installs ingress-nginx, loads the local app images plus RabbitMQ, Redis, Prometheus, and Grafana, writes `app-credentials` when that Secret is absent, applies the Kustomize tree, and waits until each Deployment is ready. Destroy deletes the kind cluster and the Compose dependency volumes.

Build the API, worker, and mock images first. Then:

```sh
terraform -chdir=deploy/terraform init
terraform -chdir=deploy/terraform apply
terraform -chdir=deploy/terraform destroy
```

`scripts/cluster-up.sh` and `scripts/deploy.sh` run apply. `scripts/cleanup.sh` runs destroy. CI sets `IMAGE_TAG` to the 12-character git SHA before apply, which selects those image tags. Omit it to use `devops-takehome-api:local`, `devops-takehome-worker:local`, and `devops-takehome-mock:1.0.0`.

State is local, at `deploy/terraform/terraform.tfstate`. It contains the generated passwords. It is gitignored, along with `.terraform/`. Do not commit it. Changing `deploy/kind/cluster.yaml` replaces the cluster. Changing a Kustomize manifest or `TF_VAR_image_tag` reapplies the workloads.

### Time

Timed implementation on 24 Sep 2026 was about 45 minutes, from the API and worker images through this note (roughly 13:25–14:05 America/Toronto). Tool installs and the first Compose test were before that clock. Work stopped under the four-hour cap.

Completed in that window: API and worker images, kind deploy, ingress limited to `/jobs`, GitHub Actions pipeline (Jenkinsfile is the same script), Prometheus and Grafana, worker restart and scale, and a check that NetworkPolicy is enforced. Terraform, queue-based worker scaling, hostPath disks, alerts, the local registry, and the failure drills were added after that timed window.

Next, if more time were available: a second kind node so Redis and RabbitMQ can fail off this node, and a backup copied off the node disk.

### Production follow-ups

Workers scale from queue depth. This RabbitMQ image does not export queue age. The hostPath volumes survive a pod delete and are gone with the kind node. Publish and the Redis write are not one transaction, and a crash after the mock call can repeat work. Terminal state expires with `RESULT_TTL_SECONDS`. Malformed messages are dropped with no dead-letter queue. Those stay application limits; this deployment does not change them.
