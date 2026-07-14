#!/usr/bin/env bash
#
# install-runner.sh - download and install the GitHub Actions runner.
#
# Reads RUNNER_VERSION and TARGETARCH from the environment. Installs into
# RUNNER_HOME (default /home/runner) and runs the runner's own dependency
# installer. Intended to run as root during the image build.
#
# Set SKIP_INSTALLDEPS=true to skip ./bin/installdependencies.sh. That helper
# shells out to a system package manager (apt/yum/dnf); on base images that
# lack one (e.g. ubi9-minimal) the .NET runtime dependencies must instead be
# installed up front by the distro's install-base.sh.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=helpers.sh
source "${SCRIPT_DIR}/helpers.sh"

RUNNER_HOME="${RUNNER_HOME:-/home/runner}"
RUNNER_USER="${RUNNER_USER:-runner}"

# map_arch maps a Docker TARGETARCH value to the runner release arch string.
# Pure function so it can be unit tested by sourcing this file.
map_arch() {
  local target_arch="$1"
  case "${target_arch}" in
    amd64 | x64 | x86_64)
      printf 'x64'
      ;;
    arm64 | aarch64)
      printf 'arm64'
      ;;
    *)
      err "Unsupported architecture: ${target_arch}"
      return 1
      ;;
  esac
}

main() {
  local runner_version="${RUNNER_VERSION:-}"
  local target_arch="${TARGETARCH:-amd64}"

  if [[ -z "${runner_version}" ]]; then
    err "RUNNER_VERSION is required"
    return 1
  fi

  local arch
  arch="$(map_arch "${target_arch}")"

  local tarball="actions-runner-linux-${arch}-${runner_version}.tar.gz"
  local url="https://github.com/actions/runner/releases/download/v${runner_version}/${tarball}"

  info "Installing GitHub Actions runner ${runner_version} (${arch}) into ${RUNNER_HOME}"
  mkdir -p "${RUNNER_HOME}"
  cd "${RUNNER_HOME}"

  info "Downloading ${url}"
  curl -fsSL -o "${tarball}" "${url}"

  info "Extracting ${tarball}"
  tar xzf "${tarball}"
  rm -f "${tarball}"

  if [[ "${SKIP_INSTALLDEPS:-}" == "true" ]]; then
    info "Skipping ./bin/installdependencies.sh (SKIP_INSTALLDEPS=true); runtime dependencies must be provided by install-base.sh"
  else
    info "Installing runner dependencies"
    ./bin/installdependencies.sh
  fi

  # Record the installed version so it can be verified without invoking the
  # runner (config.sh has no --version interface).
  printf '%s\n' "${runner_version}" > "${RUNNER_HOME}/.runner-version"

  info "Fixing ownership to ${RUNNER_USER}"
  chown -R "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_HOME}"

  info "Runner install complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
