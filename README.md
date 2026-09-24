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
