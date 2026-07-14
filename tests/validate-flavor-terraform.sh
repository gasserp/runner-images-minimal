#!/usr/bin/env bash
#
# validate-flavor-terraform.sh - black-box checks against a *built* terraform
# flavor image.
#
# Composes the base contract (tests/validate-image.sh) with terraform-specific
# checks. The flavor image is layered on a runner base, so it must still satisfy
# every base check (runner user, sudo, runner install, entrypoint fail-fast) as
# well as carrying a pinned terraform binary and the flavor's env defaults.
#
# Usage:
#   tests/validate-flavor-terraform.sh [IMAGE_TAG]
#
# IMAGE_TAG defaults to runner-images-minimal:terraform. This script does not
# build the image; run `make build-flavor` (or the CI build step) first.
#
# EXPECTED_TERRAFORM_VERSION overrides the terraform version to expect; if
# unset it is parsed from the flavor Dockerfile's ARG TERRAFORM_VERSION default.
#
# EXPECTED_RUNNER_VERSION, if set, is exported so the base-contract check
# (validate-image.sh) validates against that version instead of the checkout's
# Dockerfile default (used by release.yml to check against the released
# version). When unset, validate-image.sh's own fallback reads the ubuntu
# Dockerfile default, which matches the base the flavor is built from in CI.

set -uo pipefail

IMAGE="${1:-runner-images-minimal:terraform}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
FLAVOR_DOCKERFILE="${SCRIPT_DIR}/../images/flavors/terraform/Dockerfile"

# Propagate EXPECTED_RUNNER_VERSION to validate-image.sh so callers (e.g. the
# release workflow) can pin the base contract to the released runner version.
export EXPECTED_RUNNER_VERSION="${EXPECTED_RUNNER_VERSION:-}"

PASS_COUNT=0
FAIL_COUNT=0

# pass/fail print a uniform PASS/FAIL line and track counts.
pass() {
  printf 'PASS: %s\n' "$*"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf 'FAIL: %s\n' "$*"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# default_terraform_version extracts the default TERRAFORM_VERSION build-arg
# value from the flavor Dockerfile, e.g. `ARG TERRAFORM_VERSION=1.9.8` -> `1.9.8`.
default_terraform_version() {
  local file="$1"
  grep -m1 -E '^ARG TERRAFORM_VERSION=' "${file}" | cut -d= -f2
}

EXPECTED_TERRAFORM_VERSION="${EXPECTED_TERRAFORM_VERSION:-$(default_terraform_version "${FLAVOR_DOCKERFILE}")}"

if [[ -z "${EXPECTED_TERRAFORM_VERSION}" ]]; then
  printf 'ERROR: could not determine the expected TERRAFORM_VERSION from %s\n' \
    "${FLAVOR_DOCKERFILE}" >&2
  exit 1
fi

## --- base contract --------------------------------------------------------

# The flavor is a runner image first: run the full base validation before the
# terraform-specific checks. If EXPECTED_RUNNER_VERSION is unset, unset it here
# too so validate-image.sh applies its own Dockerfile-default fallback rather
# than seeing an empty override and erroring out.
if [[ -z "${EXPECTED_RUNNER_VERSION}" ]]; then
  unset EXPECTED_RUNNER_VERSION
fi

printf '>>> Validating base contract for flavor image %s\n' "${IMAGE}"
if "${SCRIPT_DIR}/validate-image.sh" "${IMAGE}"; then
  pass "base image contract (validate-image.sh) passes"
else
  fail "base image contract (validate-image.sh) passes"
fi

## --- terraform-specific checks --------------------------------------------

printf '>>> Validating terraform flavor extras (expecting terraform %s)\n' \
  "${EXPECTED_TERRAFORM_VERSION}"

# terraform version prints e.g. `Terraform v1.9.8` on its first line.
TERRAFORM_VERSION_OUTPUT="$(docker run --rm --entrypoint terraform "${IMAGE}" version 2>&1)"

if [[ "${TERRAFORM_VERSION_OUTPUT}" == *"Terraform v${EXPECTED_TERRAFORM_VERSION}"* ]]; then
  pass "terraform executes and reports version ${EXPECTED_TERRAFORM_VERSION}"
else
  fail "terraform executes and reports version ${EXPECTED_TERRAFORM_VERSION} (got: ${TERRAFORM_VERSION_OUTPUT})"
fi

# The image config must advertise the terraform label and disable the runner
# self-update by default. Inspect the baked-in Config.Env rather than a running
# container so the defaults are checked, not a run-time override.
IMAGE_ENV="$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${IMAGE}")"

if [[ "${IMAGE_ENV}" == *"RUNNER_LABELS="*"terraform"* ]]; then
  pass "RUNNER_LABELS in image config contains terraform"
else
  fail "RUNNER_LABELS in image config contains terraform (env: ${IMAGE_ENV})"
fi

if [[ "${IMAGE_ENV}" == *"RUNNER_DISABLE_UPDATE=true"* ]]; then
  pass "RUNNER_DISABLE_UPDATE=true is set in image config"
else
  fail "RUNNER_DISABLE_UPDATE=true is set in image config (env: ${IMAGE_ENV})"
fi

## --- summary ---------------------------------------------------------------

printf '\n%d passed, %d failed\n' "${PASS_COUNT}" "${FAIL_COUNT}"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi

exit 0
