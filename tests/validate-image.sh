#!/usr/bin/env bash
#
# validate-image.sh - black-box checks against a *built* runner image.
#
# Runs a series of `docker run` checks against the image and prints a
# PASS/FAIL line for each. Exits non-zero if any check fails.
#
# Usage:
#   tests/validate-image.sh [IMAGE_TAG]
#
# IMAGE_TAG defaults to runner-images-minimal:local. This script does not
# build the image; run `make build` (or the CI build step) first.
#
# Optionally set EXPECTED_RUNNER_VERSION to compare against the version
# baked into the image; it defaults to the RUNNER_VERSION build-arg default
# declared in images/ubuntu/Dockerfile.
#
# shellcheck disable=SC2016
# The single-quoted `[ ... ]` / shell snippets below are intentional: they
# are passed as the -lc argument to `docker run ... /bin/bash -lc '...'` and
# must expand *inside the container's* shell, not in this script.

set -uo pipefail

IMAGE="${1:-runner-images-minimal:local}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
DOCKERFILE="${SCRIPT_DIR}/../images/ubuntu/Dockerfile"

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

# check runs a description and a command; the command must print truthy
# output or exit 0 to pass. Kept generic so individual checks stay short.
check() {
  local description="$1"
  shift
  if "$@"; then
    pass "${description}"
  else
    fail "${description}"
  fi
}

# default_runner_version extracts the default RUNNER_VERSION build-arg value
# from the Dockerfile, e.g. `ARG RUNNER_VERSION=2.317.0` -> `2.317.0`.
default_runner_version() {
  local file="$1"
  grep -m1 -E '^ARG RUNNER_VERSION=' "${file}" | cut -d= -f2
}

EXPECTED_RUNNER_VERSION="${EXPECTED_RUNNER_VERSION:-$(default_runner_version "${DOCKERFILE}")}"

if [[ -z "${EXPECTED_RUNNER_VERSION}" ]]; then
  printf 'ERROR: could not determine the expected RUNNER_VERSION from %s\n' "${DOCKERFILE}" >&2
  exit 1
fi

printf '>>> Validating image %s (expecting runner version %s)\n' \
  "${IMAGE}" "${EXPECTED_RUNNER_VERSION}"

# run_in_image runs a command inside the image with a shell entrypoint,
# discarding stdout/stderr, and reports success/failure via exit status.
# Invoked indirectly as an argument to check() below, so shellcheck can't
# see the call site.
# shellcheck disable=SC2317
run_in_image() {
  docker run --rm --entrypoint /bin/bash "${IMAGE}" -lc "$1" >/dev/null 2>&1
}

# run_in_image_output runs a command inside the image with a shell
# entrypoint and prints its combined stdout+stderr.
run_in_image_output() {
  docker run --rm --entrypoint /bin/bash "${IMAGE}" -lc "$1" 2>&1
}

## --- user / permissions -------------------------------------------------

check "runner user exists with uid 1001" \
  run_in_image '[ "$(id -u runner)" = "1001" ]'

check "current container user is runner (not root)" \
  run_in_image '[ "$(whoami)" = "runner" ]'

check "sudo works passwordlessly for the runner user" \
  run_in_image 'sudo -n true'

## --- required binaries ---------------------------------------------------

for bin in git curl jq tar unzip; do
  check "required binary present: ${bin}" \
    run_in_image "command -v ${bin} >/dev/null"
done

## --- actions/runner installation -----------------------------------------

check "runner home directory exists" \
  run_in_image '[ -d "${HOME}" ]'

check "config.sh is present and executable" \
  run_in_image '[ -x "${HOME}/config.sh" ]'

check "run.sh is present and executable" \
  run_in_image '[ -x "${HOME}/run.sh" ]'

check "entrypoint.sh is present and executable" \
  run_in_image '[ -x "${HOME}/entrypoint.sh" ]'

# actions/runner does not ship a plain version file; ask the installed
# config.sh itself, which prints a version banner (`./config.sh --version`).
INSTALLED_VERSION="$(run_in_image_output 'cd "${HOME}" && ./config.sh --version 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -n1')"

if [[ "${INSTALLED_VERSION}" == *"${EXPECTED_RUNNER_VERSION}"* ]]; then
  pass "installed runner version matches expected ${EXPECTED_RUNNER_VERSION} (found: ${INSTALLED_VERSION:-unknown})"
else
  fail "installed runner version does not match expected ${EXPECTED_RUNNER_VERSION} (found: ${INSTALLED_VERSION:-unknown})"
fi

## --- entrypoint fail-fast behaviour ---------------------------------------

MISSING_ENV_OUTPUT="$(docker run --rm "${IMAGE}" 2>&1)"
MISSING_ENV_STATUS=$?

if [[ "${MISSING_ENV_STATUS}" -ne 0 ]]; then
  pass "entrypoint exits non-zero when RUNNER_REPO_URL/RUNNER_TOKEN are missing"
else
  fail "entrypoint exits non-zero when RUNNER_REPO_URL/RUNNER_TOKEN are missing (got status 0)"
fi

if [[ "${MISSING_ENV_OUTPUT}" == *"RUNNER_REPO_URL is required"* ]]; then
  pass "entrypoint prints a clear error message about the missing RUNNER_REPO_URL"
else
  fail "entrypoint prints a clear error message about the missing RUNNER_REPO_URL (got: ${MISSING_ENV_OUTPUT})"
fi

MISSING_TOKEN_OUTPUT="$(docker run --rm -e RUNNER_REPO_URL=https://github.com/owner/repo "${IMAGE}" 2>&1)"
MISSING_TOKEN_STATUS=$?

if [[ "${MISSING_TOKEN_STATUS}" -ne 0 ]]; then
  pass "entrypoint exits non-zero when only RUNNER_TOKEN is missing"
else
  fail "entrypoint exits non-zero when only RUNNER_TOKEN is missing (got status 0)"
fi

if [[ "${MISSING_TOKEN_OUTPUT}" == *"RUNNER_TOKEN is required"* ]]; then
  pass "entrypoint prints a clear error message about the missing RUNNER_TOKEN"
else
  fail "entrypoint prints a clear error message about the missing RUNNER_TOKEN (got: ${MISSING_TOKEN_OUTPUT})"
fi

## --- summary ---------------------------------------------------------------

printf '\n%d passed, %d failed\n' "${PASS_COUNT}" "${FAIL_COUNT}"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi

exit 0
