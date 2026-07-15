#!/usr/bin/env bash
#
# validate-flavor.sh - black-box checks against a *built* flavor image.
#
# Composes the base contract (tests/validate-image.sh) with flavor-specific
# checks. The flavor image is layered on a runner base, so it must still satisfy
# every base check as well as carrying the flavor's tooling and env defaults.
#
# Usage:
#   tests/validate-flavor.sh FLAVOR [IMAGE_TAG]
#
# FLAVOR selects which flavor to validate (e.g. node, python, java, etc).
# IMAGE_TAG defaults to runner-images-minimal:<FLAVOR>. This script does not
# build the image; run `make build-flavor FLAVOR=<flavor>` (or the CI build step) first.
#
# EXPECTED_RUNNER_VERSION overrides the runner version to expect; if unset it
# is parsed from the base Dockerfile's RUNNER_VERSION default.
#
# EXPECTED_<TOOL>_VERSION env vars can be set to override specific tool versions;
# otherwise they are read from the flavor Dockerfile's ARG defaults.

set -uo pipefail

FLAVOR="${1:?usage: tests/validate-flavor.sh FLAVOR [IMAGE_TAG]}"
IMAGE="${2:-runner-images-minimal:${FLAVOR}}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
FLAVOR_DOCKERFILE="${SCRIPT_DIR}/../images/flavors/${FLAVOR}/Dockerfile"

# Propagate EXPECTED_RUNNER_VERSION to validate-image.sh so callers can pin
# the base contract to a released version.
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

# dockerfile_arg_default extracts the default value of a build-arg from the flavor Dockerfile.
dockerfile_arg_default() {
  local file="$1"
  local arg_name="$2"
  grep -m1 -E "^ARG ${arg_name}=" "${file}" | cut -d= -f2
}

# Check if we're dealing with terraform and delegate to the existing script
if [[ "${FLAVOR}" == "terraform" ]]; then
  exec "${SCRIPT_DIR}/validate-flavor-terraform.sh" "${IMAGE}"
fi

## --- base contract --------------------------------------------------------

# The flavor is a runner image first: run the full base validation before the
# flavor-specific checks. If EXPECTED_RUNNER_VERSION is unset, unset it here
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

## --- flavor-specific checks ----------------------------------------------

printf '>>> Validating %s flavor extras\n' "${FLAVOR}"

# Check the image config env for required labels and disable update flag
IMAGE_ENV="$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${IMAGE}")"

if [[ "${IMAGE_ENV}" == *"RUNNER_LABELS="*"${FLAVOR}"* ]]; then
  pass "RUNNER_LABELS in image config contains ${FLAVOR}"
else
  fail "RUNNER_LABELS in image config contains ${FLAVOR} (env: ${IMAGE_ENV})"
fi

if [[ "${IMAGE_ENV}" == *"RUNNER_DISABLE_UPDATE=true"* ]]; then
  pass "RUNNER_DISABLE_UPDATE=true is set in image config"
else
  fail "RUNNER_DISABLE_UPDATE=true is set in image config (env: ${IMAGE_ENV})"
fi

# Run flavor-specific tool checks via a case statement on FLAVOR
case "${FLAVOR}" in
  node)
    EXPECTED_NODE_VERSION="${EXPECTED_NODE_VERSION:-$(dockerfile_arg_default "${FLAVOR_DOCKERFILE}" NODE_VERSION)}"

    if [[ -z "${EXPECTED_NODE_VERSION}" ]]; then
      fail "could not determine the expected NODE_VERSION from ${FLAVOR_DOCKERFILE}"
      exit 1
    fi

    NODE_VERSION_OUTPUT="$(docker run --rm --entrypoint node "${IMAGE}" --version 2>&1)"

    if [[ "${NODE_VERSION_OUTPUT}" == *"v${EXPECTED_NODE_VERSION}"* ]]; then
      pass "node executes and reports version v${EXPECTED_NODE_VERSION}"
    else
      fail "node executes and reports version v${EXPECTED_NODE_VERSION} (got: ${NODE_VERSION_OUTPUT})"
    fi

    NPM_VERSION_OUTPUT="$(docker run --rm --entrypoint npm "${IMAGE}" --version 2>&1)"

    if docker run --rm --entrypoint npm "${IMAGE}" --version >/dev/null 2>&1; then
      pass "npm executes successfully"
    else
      fail "npm executes successfully (got: ${NPM_VERSION_OUTPUT})"
    fi
    ;;

  go)
    EXPECTED_GO_VERSION="${EXPECTED_GO_VERSION:-$(dockerfile_arg_default "${FLAVOR_DOCKERFILE}" GO_VERSION)}"

    if [[ -z "${EXPECTED_GO_VERSION}" ]]; then
      fail "could not determine the expected GO_VERSION from ${FLAVOR_DOCKERFILE}"
      exit 1
    fi

    GO_VERSION_OUTPUT="$(docker run --rm --entrypoint go "${IMAGE}" version 2>&1)"

    if [[ "${GO_VERSION_OUTPUT}" == *"go${EXPECTED_GO_VERSION}"* ]]; then
      pass "go executes and reports version go${EXPECTED_GO_VERSION}"
    else
      fail "go executes and reports version go${EXPECTED_GO_VERSION} (got: ${GO_VERSION_OUTPUT})"
    fi
    ;;

  dart)
    EXPECTED_DART_VERSION="${EXPECTED_DART_VERSION:-$(dockerfile_arg_default "${FLAVOR_DOCKERFILE}" DART_VERSION)}"

    if [[ -z "${EXPECTED_DART_VERSION}" ]]; then
      fail "could not determine the expected DART_VERSION from ${FLAVOR_DOCKERFILE}"
      exit 1
    fi

    DART_VERSION_OUTPUT="$(docker run --rm --entrypoint dart "${IMAGE}" --version 2>&1)"

    if [[ "${DART_VERSION_OUTPUT}" == *"${EXPECTED_DART_VERSION}"* ]]; then
      pass "dart executes and reports version ${EXPECTED_DART_VERSION}"
    else
      fail "dart executes and reports version ${EXPECTED_DART_VERSION} (got: ${DART_VERSION_OUTPUT})"
    fi
    ;;

  rust)
    EXPECTED_RUST_VERSION="${EXPECTED_RUST_VERSION:-$(dockerfile_arg_default "${FLAVOR_DOCKERFILE}" RUST_VERSION)}"

    if [[ -z "${EXPECTED_RUST_VERSION}" ]]; then
      fail "could not determine the expected RUST_VERSION from ${FLAVOR_DOCKERFILE}"
      exit 1
    fi

    RUSTC_VERSION_OUTPUT="$(docker run --rm --entrypoint rustc "${IMAGE}" --version 2>&1)"

    if [[ "${RUSTC_VERSION_OUTPUT}" == *"${EXPECTED_RUST_VERSION}"* ]]; then
      pass "rustc executes and reports version ${EXPECTED_RUST_VERSION}"
    else
      fail "rustc executes and reports version ${EXPECTED_RUST_VERSION} (got: ${RUSTC_VERSION_OUTPUT})"
    fi

    CARGO_VERSION_OUTPUT="$(docker run --rm --entrypoint cargo "${IMAGE}" --version 2>&1)"

    if [[ "${CARGO_VERSION_OUTPUT}" == *"${EXPECTED_RUST_VERSION}"* ]]; then
      pass "cargo executes and reports version ${EXPECTED_RUST_VERSION}"
    else
      fail "cargo executes and reports version ${EXPECTED_RUST_VERSION} (got: ${CARGO_VERSION_OUTPUT})"
    fi
    ;;

  php)
    PHP_VERSION_OUTPUT="$(docker run --rm --entrypoint php "${IMAGE}" --version 2>&1)"

    if [[ "${PHP_VERSION_OUTPUT}" == *"PHP"* ]]; then
      pass "php executes and reports version containing PHP"
    else
      fail "php executes and reports version containing PHP (got: ${PHP_VERSION_OUTPUT})"
    fi

    EXPECTED_COMPOSER_VERSION="${EXPECTED_COMPOSER_VERSION:-$(dockerfile_arg_default "${FLAVOR_DOCKERFILE}" COMPOSER_VERSION)}"

    if [[ -z "${EXPECTED_COMPOSER_VERSION}" ]]; then
      fail "could not determine the expected COMPOSER_VERSION from ${FLAVOR_DOCKERFILE}"
      exit 1
    fi

    COMPOSER_VERSION_OUTPUT="$(docker run --rm -e COMPOSER_ALLOW_SUPERUSER=1 --entrypoint composer "${IMAGE}" --version 2>&1)"

    if [[ "${COMPOSER_VERSION_OUTPUT}" == *"${EXPECTED_COMPOSER_VERSION}"* ]]; then
      pass "composer executes and reports version ${EXPECTED_COMPOSER_VERSION}"
    else
      fail "composer executes and reports version ${EXPECTED_COMPOSER_VERSION} (got: ${COMPOSER_VERSION_OUTPUT})"
    fi
    ;;

  python)
    PYTHON3_VERSION_OUTPUT="$(docker run --rm --entrypoint python3 "${IMAGE}" --version 2>&1)"

    if [[ "${PYTHON3_VERSION_OUTPUT}" == *"Python 3"* ]]; then
      pass "python3 executes and reports version containing Python 3"
    else
      fail "python3 executes and reports version containing Python 3 (got: ${PYTHON3_VERSION_OUTPUT})"
    fi

    PIP3_VERSION_OUTPUT="$(docker run --rm --entrypoint pip3 "${IMAGE}" --version 2>&1)"

    if docker run --rm --entrypoint pip3 "${IMAGE}" --version >/dev/null 2>&1; then
      pass "pip3 executes successfully"
    else
      fail "pip3 executes successfully (got: ${PIP3_VERSION_OUTPUT})"
    fi
    ;;

  java)
    JAVA_VERSION_OUTPUT="$(docker run --rm --entrypoint java "${IMAGE}" -version 2>&1)"

    if [[ "${JAVA_VERSION_OUTPUT}" == *"openjdk"* ]]; then
      pass "java executes and reports version containing openjdk"
    else
      fail "java executes and reports version containing openjdk (got: ${JAVA_VERSION_OUTPUT})"
    fi

    MVN_VERSION_OUTPUT="$(docker run --rm --entrypoint mvn "${IMAGE}" -version 2>&1)"

    if [[ "${MVN_VERSION_OUTPUT}" == *"Apache Maven"* ]]; then
      pass "mvn executes and reports version containing Apache Maven"
    else
      fail "mvn executes and reports version containing Apache Maven (got: ${MVN_VERSION_OUTPUT})"
    fi
    ;;

  ruby)
    RUBY_VERSION_OUTPUT="$(docker run --rm --entrypoint ruby "${IMAGE}" --version 2>&1)"

    if [[ "${RUBY_VERSION_OUTPUT}" == *"ruby"* ]]; then
      pass "ruby executes and reports version containing ruby"
    else
      fail "ruby executes and reports version containing ruby (got: ${RUBY_VERSION_OUTPUT})"
    fi

    GEM_VERSION_OUTPUT="$(docker run --rm --entrypoint gem "${IMAGE}" --version 2>&1)"

    if docker run --rm --entrypoint gem "${IMAGE}" --version >/dev/null 2>&1; then
      pass "gem executes successfully"
    else
      fail "gem executes successfully (got: ${GEM_VERSION_OUTPUT})"
    fi
    ;;

  dotnet)
    DOTNET_STATUS=0
    DOTNET_VERSION_OUTPUT="$(docker run --rm --entrypoint dotnet "${IMAGE}" --list-sdks 2>&1)" || DOTNET_STATUS=$?

    if [[ "${DOTNET_STATUS}" -eq 0 && -n "${DOTNET_VERSION_OUTPUT}" ]]; then
      pass "dotnet executes and lists SDKs"
    else
      fail "dotnet executes and lists SDKs (got error: ${DOTNET_VERSION_OUTPUT})"
    fi
    ;;

  *)
    printf 'ERROR: unknown flavor %s\n' "${FLAVOR}" >&2
    exit 1
    ;;
esac

## --- summary ---------------------------------------------------------------

printf '\n%d passed, %d failed\n' "${PASS_COUNT}" "${FAIL_COUNT}"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi

exit 0