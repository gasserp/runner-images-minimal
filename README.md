# runner-images-minimal

A minimal, containerized self-hosted [GitHub Actions runner](https://github.com/actions/runner)
image. It installs only the packages needed to fetch and run the runner,
registers itself against a repository using a short-lived registration token,
and deregisters cleanly on shutdown.

Two base distributions are supported, selected with the `DISTRO` variable:

| `DISTRO` | Base image                                          | Package manager |
| -------- | --------------------------------------------------- | --------------- |
| `ubuntu` | `ubuntu:24.04` (default)                            | `apt`           |
| `ubi9`   | `registry.access.redhat.com/ubi9-minimal`           | `microdnf`      |

The entrypoint and runner-install logic are shared between the two images
(`images/common/`); only the base-package install differs per distro.

## Features

- Small, single-stage images on Ubuntu 24.04 or RHEL UBI9-minimal.
- Non-root `runner` user (uid 1001) with passwordless sudo.
- Multi-arch aware (`amd64` / `arm64`) via the Docker `TARGETARCH` build arg.
- Clean registration and deregistration (SIGTERM/SIGINT deregister the runner).
- Optional ephemeral mode for one-job-per-container setups.
- Modular, idempotent, `shellcheck`-clean install scripts with unit tests.

## Quick start

Build the image (optionally pin a runner version). `DISTRO` defaults to
`ubuntu`; pass `DISTRO=ubi9` for the UBI9-minimal image:

```sh
make build RUNNER_VERSION=2.317.0            # ubuntu (default)
make build DISTRO=ubi9                       # RHEL UBI9-minimal
make build-all                               # both images

# or directly (note the build context is images/, with -f selecting the distro):
docker build --build-arg RUNNER_VERSION=2.317.0 \
  -t runner-images-minimal:ubuntu -f images/ubuntu/Dockerfile images
docker build \
  -t runner-images-minimal:ubi9 -f images/ubi9/Dockerfile images
```

Each `make build` tags the image `runner-images-minimal:$(DISTRO)` by default
(override with `IMAGE=`).

Get a registration token from your repository settings
(`Settings -> Actions -> Runners -> New self-hosted runner`), or via the API,
then run:

```sh
docker run --rm -it \
  -e RUNNER_REPO_URL=https://github.com/OWNER/REPO \
  -e RUNNER_TOKEN=YOUR_REGISTRATION_TOKEN \
  runner-images-minimal:ubuntu
```

The `make run` target wraps the same command and honours `DISTRO` (it runs the
`runner-images-minimal:$(DISTRO)` tag):

```sh
make run RUNNER_REPO_URL=https://github.com/OWNER/REPO RUNNER_TOKEN=xxxx
make run DISTRO=ubi9 RUNNER_REPO_URL=https://github.com/OWNER/REPO RUNNER_TOKEN=xxxx
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
| `RUNNER_DISABLE_UPDATE` | no  | `false`                    | Set to `true` to add `--disableupdate` (skip runner self-update). Defaults to `true` in flavor images. |

Build-time args:

| Arg                | Default   | Description                                    |
| ------------------ | --------- | ---------------------------------------------- |
| `RUNNER_VERSION`   | `2.317.0` | `actions/runner` release to install.           |
| `TERRAFORM_VERSION`| `1.9.8`   | Terraform release baked into the terraform flavor image. |
| `TARGETARCH`       | `amd64`   | Target architecture (auto-set under BuildKit). |

Make variables:

| Variable         | Default                        | Description                                        |
| ---------------- | ------------------------------ | -------------------------------------------------- |
| `DISTRO`         | `ubuntu`                       | Which image to build/run (`ubuntu` or `ubi9`).     |
| `IMAGE`          | `runner-images-minimal:$(DISTRO)` | Image tag used by `build`, `run` and `validate`. |
| `RUNNER_VERSION` | `2.317.0`                      | Runner release passed as a build arg.              |
| `FLAVOR_IMAGE`   | `runner-images-minimal:terraform` | Tag used by `build-flavor` and `validate-flavor`. |
| `TERRAFORM_VERSION` | `1.9.8`                     | Terraform release baked into the terraform flavor. |

## Flavors

Flavor images layer extra tooling onto a base runner image. They exist for
**ephemeral runner fleets**, where a runner handles a single job and is then
destroyed: installing tools at job time would repeat a download on every job
and add a point of network failure mid-job. Flavors instead **bake the tools
into the image at build time** (checksum-verified and version-pinned), so jobs
start with everything already present and never install anything.

Flavors also default `RUNNER_DISABLE_UPDATE=true`: an ephemeral runner would
otherwise re-download a runner self-update on nearly every job start. Override
it at run time with `-e RUNNER_DISABLE_UPDATE=false` if you want self-updates.

### terraform

Bakes a pinned [Terraform](https://www.terraform.io/) into the `ubuntu` base
and advertises a `terraform` label so workflows can target it with
`runs-on: [self-hosted, terraform]` without any deploy-time label config.

```sh
# Build the ubuntu base, then layer the terraform flavor on top of it:
make build DISTRO=ubuntu
make build-flavor                              # tags runner-images-minimal:terraform
make build-flavor TERRAFORM_VERSION=1.9.8      # pin a specific Terraform version

# or directly (build context is images/):
docker build \
  --build-arg BASE_IMAGE=runner-images-minimal:ubuntu \
  --build-arg TERRAFORM_VERSION=1.9.8 \
  -t runner-images-minimal:terraform \
  -f images/flavors/terraform/Dockerfile images

# Validate the built flavor image (base contract + terraform checks):
make validate-flavor
```

Run it like any other runner image; the `terraform` label is already set:

```sh
docker run --rm -it \
  -e RUNNER_REPO_URL=https://github.com/OWNER/REPO \
  -e RUNNER_TOKEN=YOUR_REGISTRATION_TOKEN \
  runner-images-minimal:terraform
```

## Layout

Shared, distro-agnostic code lives in `images/common/`; each distro directory
holds only its `Dockerfile` and its `install-base.sh`. The Docker build context
is `images/` (not `images/<distro>/`) so the Dockerfiles can `COPY` the shared
files; the distro is selected with `-f images/<distro>/Dockerfile`.

```
.
├── Makefile                     # build / build-all / build-flavor / lint / test / validate / validate-flavor / run
├── README.md
├── .gitignore
├── .dockerignore                # applies to root-context builds
├── .hadolint.yaml               # hadolint config (Dockerfile lint)
├── .github/
│   └── workflows/
│       └── ci.yml               # lint + unit-tests + build-and-validate
├── images/
│   ├── .dockerignore            # applies to the images/ build context
│   ├── common/                  # shared, distro-agnostic code
│   │   ├── entrypoint.sh        # configures + runs the runner (as runner user)
│   │   ├── helpers.sh           # shared logging helpers (sourced)
│   │   └── install-runner.sh    # downloads + installs actions/runner
│   ├── ubuntu/
│   │   ├── Dockerfile           # ubuntu:24.04 based image
│   │   └── scripts/
│   │       └── install-base.sh  # apt base packages
│   ├── ubi9/
│   │   ├── Dockerfile           # ubi9-minimal based image
│   │   └── scripts/
│   │       └── install-base.sh  # microdnf base packages + .NET deps
│   └── flavors/                 # tooling layered on a base image
│       └── terraform/
│           ├── Dockerfile       # FROM a base image + baked-in Terraform
│           └── scripts/
│               └── install-terraform.sh # downloads + checksum-verifies Terraform
└── tests/
    ├── entrypoint.bats          # unit tests for entrypoint (incl. mocked main())
    ├── helpers.bats             # unit tests for the logging helpers
    ├── install-base-ubuntu.bats # unit tests for ubuntu's base package list
    ├── install-base-ubi9.bats   # unit tests for ubi9's base package list
    ├── install-runner.bats      # unit tests for arch mapping + main() guards
    ├── lib/
    │   └── install-base-common.bash # shared setup/assertions for both install-base-*.bats
    ├── validate-image.sh        # black-box checks against a *built* image
    └── validate-flavor-terraform.sh # base contract + terraform checks for the flavor
```

### Distro notes

- **Ubuntu** installs base packages with `apt` and lets the runner's own
  `./bin/installdependencies.sh` pull in the .NET runtime dependencies. The
  base package list was trimmed — `gnupg` and `lsb-release` are no longer
  installed, as the runner does not need them.
- **UBI9-minimal** has no `yum`/`dnf`, so `./bin/installdependencies.sh` cannot
  run; `install-runner.sh` is invoked with `SKIP_INSTALLDEPS=true` and the .NET
  runtime dependencies (`libicu`, `krb5-libs`, `openssl-libs`, `zlib`) are
  installed explicitly by its `install-base.sh` via `microdnf`, with
  `lttng-ust` (optional .NET tracing) attempted best-effort since it may be
  missing from the freely available UBI repos. `curl` is not installed because
  the base image's `curl-minimal` already provides it (and conflicts with the
  full package). The `runner` user is created after the base install because
  `useradd` (from `shadow-utils`) is not present until then, and the
  `en_US.UTF-8` locale comes from `glibc-langpack-en` (no `locale-gen` step).
- **Alpine** is intentionally not supported: `actions/runner` ships only
  glibc-linked Linux binaries, with no official musl build, so it cannot run on
  a musl-based Alpine image without an unsupported compatibility shim.

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
  `tests/validate-image.sh` and the shared scripts under `images/common/`). CI
  additionally runs [hadolint](https://github.com/hadolint/hadolint) against
  the per-distro Dockerfiles (config in `.hadolint.yaml`).
- `make test` runs the [bats](https://github.com/bats-core/bats-core) suite in
  `tests/` — pure-function unit tests plus mocked end-to-end tests, no Docker
  required.
- `make validate` runs `tests/validate-image.sh` against a **built** image
  (default tag `runner-images-minimal:$(DISTRO)`, i.e. `:ubuntu` unless
  `DISTRO`/`IMAGE` is overridden).
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

1. `lint` — shellcheck (`make lint`) + hadolint on the Ubuntu Dockerfile.
2. `unit-tests` — installs bats and runs `make test`.
3. `build-and-validate` — needs both jobs above; runs as a `fail-fast: false`
   matrix over `distro: [ubuntu, ubi9]`, building each image with
   `docker/build-push-action` (loaded locally, never pushed, using a
   distro-scoped `type=gha` cache) and running `tests/validate-image.sh`
   against it.
4. `build-and-validate-flavor` — needs both `lint` and `unit-tests`; builds the
   `ubuntu` base, layers the terraform flavor on it (`BASE_IMAGE=runner-images-minimal:ubuntu`),
   and runs `tests/validate-flavor-terraform.sh` against the result.

## Releases

Images are published to the GitHub Container Registry under
`ghcr.io/gasserp/runner-images-minimal/<distro>`, tagged with the
`actions/runner` version and `latest`:

```sh
docker pull ghcr.io/gasserp/runner-images-minimal/ubuntu:latest
docker pull ghcr.io/gasserp/runner-images-minimal/ubi9:2.317.0
docker pull ghcr.io/gasserp/runner-images-minimal/terraform:latest
```

Publishing is driven by `.github/workflows/release.yml`, which runs on a
schedule (every 6 hours) and autodetects the latest `actions/runner` release.
When a version has not been released here yet, it builds both base images with
that version, validates them with `tests/validate-image.sh`, and pushes them to
GHCR (version + `latest` tags). It then layers the terraform flavor on the
just-pushed `ubuntu` image, validates it with
`tests/validate-flavor-terraform.sh`, and pushes
`ghcr.io/gasserp/runner-images-minimal/terraform` too, before creating a
matching `v<version>` GitHub Release. It can also be triggered manually via
`workflow_dispatch`, with an optional `runner_version` input to build a
specific version instead of the autodetected latest.

Published images are **amd64-only** for now, matching CI.
