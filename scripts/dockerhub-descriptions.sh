#!/usr/bin/env bash
#
# dockerhub-descriptions.sh - generate and publish the Docker Hub repository
# descriptions for every published variant.
#
# Docker Hub has no nested repositories, so each variant lives in its own repo
# (<namespace>/runner-images-minimal-<variant>) and needs its own short
# description and overview. Both are generated from one template here so the
# twelve repo pages cannot drift apart.
#
# Usage:
#   dockerhub-descriptions.sh print <variant>   # write the overview to stdout
#   dockerhub-descriptions.sh sync              # publish all variants
#
# Required env vars for `sync`:
#   DOCKERHUB_USERNAME  - Docker Hub account used to authenticate
#   DOCKERHUB_TOKEN     - Docker Hub personal access token (read/write)
#   DOCKERHUB_NAMESPACE - namespace owning the repositories

set -euo pipefail

readonly SOURCE_URL="https://github.com/gasserp/runner-images-minimal"
readonly VARIANTS="ubuntu ubi9 terraform node python java dotnet go rust ruby php dart"

# variant_title echoes the human-readable name of a variant.
variant_title() {
  case "$1" in
    ubuntu) printf 'Ubuntu base' ;;
    ubi9) printf 'RHEL UBI9 base' ;;
    terraform) printf 'Terraform flavor' ;;
    node) printf 'Node.js flavor' ;;
    python) printf 'Python flavor' ;;
    java) printf 'Java flavor' ;;
    dotnet) printf '.NET flavor' ;;
    go) printf 'Go flavor' ;;
    rust) printf 'Rust flavor' ;;
    ruby) printf 'Ruby flavor' ;;
    php) printf 'PHP flavor' ;;
    dart) printf 'Dart flavor' ;;
    *) printf 'ERROR: unknown variant %s\n' "$1" >&2; return 1 ;;
  esac
}

# variant_short echoes the Docker Hub short description (max 100 characters).
variant_short() {
  case "$1" in
    ubuntu) printf 'Minimal self-hosted GitHub Actions runner on Ubuntu 24.04' ;;
    ubi9) printf 'Minimal self-hosted GitHub Actions runner on RHEL UBI9-minimal' ;;
    terraform) printf 'Self-hosted GitHub Actions runner with Terraform baked in' ;;
    node) printf 'Self-hosted GitHub Actions runner with Node.js and npm baked in' ;;
    python) printf 'Self-hosted GitHub Actions runner with Python 3 and pip baked in' ;;
    java) printf 'Self-hosted GitHub Actions runner with OpenJDK 21 and Maven baked in' ;;
    dotnet) printf 'Self-hosted GitHub Actions runner with the .NET SDK 8.0 baked in' ;;
    go) printf 'Self-hosted GitHub Actions runner with the Go toolchain baked in' ;;
    rust) printf 'Self-hosted GitHub Actions runner with Rust and Cargo baked in' ;;
    ruby) printf 'Self-hosted GitHub Actions runner with Ruby and Bundler baked in' ;;
    php) printf 'Self-hosted GitHub Actions runner with PHP and Composer baked in' ;;
    dart) printf 'Self-hosted GitHub Actions runner with the Dart SDK baked in' ;;
    *) printf 'ERROR: unknown variant %s\n' "$1" >&2; return 1 ;;
  esac
}

# variant_base echoes the base distribution the published image is built on.
variant_base() {
  case "$1" in
    ubi9) printf 'registry.access.redhat.com/ubi9-minimal:9.5' ;;
    *) printf 'ubuntu:24.04' ;;
  esac
}

# variant_tooling echoes the baked-in tooling and how it is installed, or an
# empty string for the two base images (which bake in no extra tooling).
# The backticks are markdown code spans, not command substitution.
# shellcheck disable=SC2016
variant_tooling() {
  case "$1" in
    terraform) printf '`terraform` — pinned tarball, checksum-verified' ;;
    node) printf '`node`, `npm`, `npx`, `corepack` — pinned tarball, checksum-verified' ;;
    python) printf '`python3`, `pip3`, `venv` — from the Ubuntu archive' ;;
    java) printf 'OpenJDK 21 (headless), `mvn` — from the Ubuntu archive' ;;
    dotnet) printf '.NET SDK 8.0 — from the Ubuntu archive' ;;
    go) printf '`go`, `gofmt` — pinned tarball, checksum-verified' ;;
    rust) printf '`rustc`, `cargo`, plus `gcc` as the linker — pinned tarball, checksum-verified' ;;
    ruby) printf '`ruby`, `gem`, `bundler`, plus build tools — from the Ubuntu archive' ;;
    php) printf '`php` CLI — from the Ubuntu archive; `composer` — pinned phar, checksum-verified' ;;
    dart) printf '`dart` — pinned zip, checksum-verified' ;;
    *) printf '' ;;
  esac
}

# variant_labels echoes the default RUNNER_LABELS baked into the image.
variant_labels() {
  case "$1" in
    ubuntu | ubi9) printf 'self-hosted,linux,minimal' ;;
    *) printf 'self-hosted,linux,minimal,%s' "$1" ;;
  esac
}

# print_overview writes the Docker Hub overview (markdown) for a variant to
# stdout. $1 variant, $2 namespace.
print_overview() {
  local variant="$1"
  local namespace="$2"
  local image="${namespace}/runner-images-minimal-${variant}"
  local tooling
  tooling="$(variant_tooling "${variant}")"

  cat <<EOF
# runner-images-minimal — $(variant_title "${variant}")

A minimal, containerized [self-hosted GitHub Actions runner](https://github.com/actions/runner).

It installs only what is needed to fetch and run the runner, registers itself
against a repository or organization with a short-lived registration token, and
deregisters cleanly when the container stops. No agents, no supervisors, no
extra services — one runner process in the foreground, so Docker, Kubernetes or
systemd stays in charge of the lifecycle.

- **Base image:** \`$(variant_base "${variant}")\`
- **Runs as** the non-root \`runner\` user (uid 1001) with passwordless sudo
- **Default labels:** \`$(variant_labels "${variant}")\`
- **Clean deregistration** on SIGTERM/SIGINT, so stopped containers do not
  leave offline runners behind in the GitHub UI
- **Ephemeral mode** for one-job-per-container fleets
- **amd64 only** for now

EOF

  if [ -n "${tooling}" ]; then
    cat <<EOF
## Baked-in tooling

${tooling}

The tooling is installed **at image build time**, version-pinned and (where an
official checksummed release artifact exists) checksum-verified. That is the
whole point of a flavor: in an ephemeral fleet, installing a toolchain during
the job would repeat the same download on every single job and add a point of
network failure mid-job.

This flavor also defaults \`RUNNER_DISABLE_UPDATE=true\`, because an ephemeral
runner would otherwise pull a runner self-update on nearly every job start.
Override it at run time with \`-e RUNNER_DISABLE_UPDATE=false\`.

EOF
  fi

  cat <<EOF
## Quick start

First get a registration token — either from
**Settings → Actions → Runners → New self-hosted runner**, or from the API:

\`\`\`sh
gh api -X POST repos/OWNER/REPO/actions/runners/registration-token --jq .token
\`\`\`

Registration tokens are short-lived (about an hour) and are only used once, at
container start. They are **not** a permanent credential — the runner exchanges
one for its own credentials during registration.

Then start the runner:

\`\`\`sh
docker run --rm -it \\
  -e RUNNER_REPO_URL=https://github.com/OWNER/REPO \\
  -e RUNNER_TOKEN=YOUR_REGISTRATION_TOKEN \\
  ${image}:latest
\`\`\`

The runner appears under **Settings → Actions → Runners** within a few seconds.
Target it from a workflow with the labels it already advertises:

\`\`\`yaml
jobs:
  build:
    runs-on: [$(variant_labels "${variant}" | tr ',' ' ' | sed 's/ /, /g')]
\`\`\`

Stop the container (\`Ctrl-C\`, \`docker stop\`) and it deregisters itself.

## Ephemeral fleets

For a one-job-per-container fleet, run with \`RUNNER_EPHEMERAL=true\`: the runner
picks up exactly one job, then exits, and your orchestrator starts a fresh
container. Every job therefore gets a guaranteed-clean filesystem.

\`\`\`sh
docker run --rm \\
  -e RUNNER_REPO_URL=https://github.com/OWNER/REPO \\
  -e RUNNER_TOKEN=YOUR_REGISTRATION_TOKEN \\
  -e RUNNER_EPHEMERAL=true \\
  ${image}:latest
\`\`\`

Each container needs its own fresh registration token.

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| \`RUNNER_REPO_URL\` | yes | — | Repository or organization URL to register against |
| \`RUNNER_TOKEN\` | yes | — | Short-lived registration token |
| \`RUNNER_NAME\` | no | container hostname | Name shown in the GitHub runners list |
| \`RUNNER_LABELS\` | no | \`$(variant_labels "${variant}")\` | Comma-separated labels |
| \`RUNNER_WORK_DIR\` | no | \`_work\` | Working directory for job checkouts |
| \`RUNNER_EPHEMERAL\` | no | \`false\` | \`true\` runs a single job, then exits |
| \`RUNNER_DISABLE_UPDATE\` | no | \`$(if [ -n "${tooling}" ]; then printf 'true'; else printf 'false'; fi)\` | \`true\` skips the runner self-update |

## Tags

- \`latest\` — the most recent build
- \`<runner-version>\` (e.g. \`2.336.0\`) — pinned to that \`actions/runner\`
  release; use this if you want reproducible fleets

A new tag is published automatically within hours of every upstream
\`actions/runner\` release.

## A note on running jobs in containers

The runner has no Docker socket and no Docker CLI. Workflows that use
\`container:\`, service containers or \`docker build\` need a Docker daemon made
available to the container — mounting the host socket grants the runner root on
the host, so treat that as a trust decision about the workflows you let run, not
a default.

## Source, other variants and issues

All twelve variants (two bases and ten language flavors), the Dockerfiles and
the build pipeline: ${SOURCE_URL}

The same images are also published to GHCR as
\`ghcr.io/gasserp/runner-images-minimal/${variant}\`.
EOF
}

# dockerhub_login echoes a Docker Hub JWT for the configured credentials.
dockerhub_login() {
  local response
  response="$(curl -sS -X POST \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg u "${DOCKERHUB_USERNAME}" --arg p "${DOCKERHUB_TOKEN}" \
      '{username: $u, password: $p}')" \
    'https://hub.docker.com/v2/users/login/')"

  local token
  token="$(printf '%s' "${response}" | jq -r '.token // empty')"
  if [ -z "${token}" ]; then
    printf 'ERROR: Docker Hub login failed: %s\n' "${response}" >&2
    return 1
  fi
  printf '%s' "${token}"
}

# sync_variant publishes one variant's descriptions. $1 jwt, $2 namespace,
# $3 variant.
sync_variant() {
  local jwt="$1"
  local namespace="$2"
  local variant="$3"
  local repo="${namespace}/runner-images-minimal-${variant}"

  local body
  body="$(jq -nc \
    --arg short "$(variant_short "${variant}")" \
    --arg full "$(print_overview "${variant}" "${namespace}")" \
    '{description: $short, full_description: $full}')"

  local status
  status="$(curl -sS -o /tmp/dockerhub-response.json -w '%{http_code}' \
    -X PATCH \
    -H "Authorization: JWT ${jwt}" \
    -H 'Content-Type: application/json' \
    -d "${body}" \
    "https://hub.docker.com/v2/repositories/${repo}/")"

  if [ "${status}" != "200" ]; then
    printf 'ERROR: %s -> HTTP %s: %s\n' "${repo}" "${status}" \
      "$(cat /tmp/dockerhub-response.json)" >&2
    return 1
  fi
  printf 'updated %s\n' "${repo}"
}

# require_env exits non-zero when a required variable is unset or empty.
require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    printf 'ERROR: %s is required\n' "${name}" >&2
    return 1
  fi
}

main() {
  local command="${1:-}"

  case "${command}" in
    print)
      local variant="${2:-}"
      if [ -z "${variant}" ]; then
        printf 'ERROR: usage: %s print <variant>\n' "$0" >&2
        return 1
      fi
      print_overview "${variant}" "${DOCKERHUB_NAMESPACE:-NAMESPACE}"
      ;;
    sync)
      require_env DOCKERHUB_USERNAME
      require_env DOCKERHUB_TOKEN
      require_env DOCKERHUB_NAMESPACE

      local jwt
      jwt="$(dockerhub_login)"

      local variant
      for variant in ${VARIANTS}; do
        sync_variant "${jwt}" "${DOCKERHUB_NAMESPACE}" "${variant}"
      done
      ;;
    *)
      printf 'ERROR: usage: %s {print <variant>|sync}\n' "$0" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
