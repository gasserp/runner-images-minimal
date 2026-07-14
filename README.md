# runner-images-minimal

A minimal, containerized self-hosted [GitHub Actions runner](https://github.com/actions/runner)
image. It builds on `ubuntu:24.04`, installs only the packages needed to fetch
and run the runner, registers itself against a repository using a short-lived
registration token, and deregisters cleanly on shutdown.

## Features

- Small, single-stage Ubuntu 24.04 image.
- Non-root `runner` user (uid 1001) with passwordless sudo.
- Multi-arch aware (`amd64` / `arm64`) via the Docker `TARGETARCH` build arg.
- Clean registration and deregistration (SIGTERM/SIGINT deregister the runner).
- Optional ephemeral mode for one-job-per-container setups.
- Modular, idempotent, `shellcheck`-clean install scripts with unit tests.

## Quick start

Build the image (optionally pin a runner version):

```sh
make build RUNNER_VERSION=2.317.0
# or directly:
docker build --build-arg RUNNER_VERSION=2.317.0 \
  -t runner-images-minimal:latest images/ubuntu
```

Get a registration token from your repository settings
(`Settings -> Actions -> Runners -> New self-hosted runner`), or via the API,
then run:

```sh
docker run --rm -it \
  -e RUNNER_REPO_URL=https://github.com/OWNER/REPO \
  -e RUNNER_TOKEN=YOUR_REGISTRATION_TOKEN \
  runner-images-minimal:latest
```

The `make run` target wraps the same command:

```sh
make run RUNNER_REPO_URL=https://github.com/OWNER/REPO RUNNER_TOKEN=xxxx
```

## Environment variables

| Variable           | Required | Default                    | Description                                             |
| ------------------ | -------- | -------------------------- | ------------------------------------------------------- |
| `RUNNER_REPO_URL`  | yes      | —                          | Repository (or org) URL to register against.            |
| `RUNNER_TOKEN`     | yes      | —                          | Short-lived runner registration token.                  |
| `RUNNER_NAME`      | no       | container hostname         | Name shown in the GitHub runners list.                  |
| `RUNNER_LABELS`    | no       | `self-hosted,linux,minimal`| Comma-separated labels applied to the runner.           |
| `RUNNER_WORK_DIR`  | no       | `_work`                    | Working directory for job checkouts.                    |
| `RUNNER_EPHEMERAL` | no       | `false`                    | Set to `true` to add `--ephemeral` (one job per runner).|

Build-time args:

| Arg              | Default   | Description                                    |
| ---------------- | --------- | ---------------------------------------------- |
| `RUNNER_VERSION` | `2.317.0` | `actions/runner` release to install.           |
| `TARGETARCH`     | `amd64`   | Target architecture (auto-set under BuildKit). |

## Layout

```
.
├── Makefile                     # build / lint / test / validate / run targets
├── README.md
├── .gitignore
├── .dockerignore
├── .hadolint.yaml                # hadolint config (Dockerfile lint)
├── .github/
│   └── workflows/
│       └── ci.yml                # lint + unit-tests + build-and-validate
├── images/
│   └── ubuntu/
│       ├── Dockerfile           # ubuntu:24.04 based image
│       ├── entrypoint.sh        # configures + runs the runner (as runner user)
│       └── scripts/
│           ├── helpers.sh       # shared logging helpers (sourced)
│           ├── install-base.sh  # apt base packages
│           └── install-runner.sh# downloads + installs actions/runner
└── tests/
    ├── entrypoint.bats          # unit tests for entrypoint (incl. mocked main())
    ├── helpers.bats             # unit tests for the logging helpers
    ├── install-base.bats        # unit tests for the base package list
    ├── install-runner.bats      # unit tests for arch mapping + main() guards
    └── validate-image.sh        # black-box checks against a *built* image
```

## Testing

The shell logic is factored into small pure functions guarded by a
`BASH_SOURCE`/`$0` check, so the scripts can be sourced by tests without
executing their `main`. Tests that need to observe `main()`'s real
control-flow (e.g. fail-fast on missing env vars, or the exact arguments
passed to `config.sh`) run it in a real `bash` subprocess against mocked
`config.sh`/`run.sh` executables, rather than via bats' `run` directly
(`run` disables `set -e` for the duration of the call, which would mask the
scripts' own `set -euo pipefail` guards).

- `make lint` runs `shellcheck -S style` on every `*.sh` file (this includes
  `tests/validate-image.sh`). CI additionally runs
  [hadolint](https://github.com/hadolint/hadolint) against
  `images/ubuntu/Dockerfile` (config in `.hadolint.yaml`).
- `make test` runs the [bats](https://github.com/bats-core/bats-core) suite in
  `tests/` — pure-function unit tests plus mocked end-to-end tests, no Docker
  required.
- `make validate` runs `tests/validate-image.sh` against a **built** image
  (default tag `runner-images-minimal:latest`, or override with `IMAGE=`).
  It checks the `runner` user (uid 1001), passwordless sudo, required
  binaries (`git`, `curl`, `jq`, `tar`, `unzip`), that `config.sh`/`run.sh`
  are present and executable, that the installed runner version matches the
  Dockerfile's `RUNNER_VERSION` build-arg default, and that the entrypoint
  fails fast with a clear error when `RUNNER_REPO_URL`/`RUNNER_TOKEN` are
  missing. Run `make build` first.

```sh
make lint
make test
make build && make validate
```

### CI

`.github/workflows/ci.yml` runs on every push to `main` and on pull
requests, with three jobs:

1. `lint` — shellcheck (`make lint`) + hadolint on the Dockerfile.
2. `unit-tests` — installs bats and runs `make test`.
3. `build-and-validate` — needs both jobs above; builds the image with
   `docker/build-push-action` (loaded locally, never pushed) and runs
   `tests/validate-image.sh` against it.
