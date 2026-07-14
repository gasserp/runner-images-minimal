#!/usr/bin/env bash
#
# install-base.sh - install the minimal base packages needed by the runner.
#
# Idempotent: re-running only reinstalls already-present packages. Intended to
# run as root during the image build.

set -euo pipefail

# The build copies helpers.sh next to this script under /tmp/scripts/, so it is
# sourced from SCRIPT_DIR at build time; the source= directive below points at
# its in-repo location for shellcheck.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../../common/helpers.sh
source "${SCRIPT_DIR}/helpers.sh"

# Packages kept deliberately small: just enough to fetch, verify and run the
# GitHub Actions runner plus common toolchain expectations (git, jq, sudo).
#
# libicu74 is required by the runner's .NET runtime. It must be installed
# explicitly: the runner's own installdependencies.sh (as of v2.317.0) only
# probes libicu72 and older, finds none of them on Ubuntu 24.04, and installs
# no ICU at all — which makes Runner.Listener crash on startup.
BASE_PACKAGES=(
  ca-certificates
  curl
  git
  jq
  tar
  unzip
  sudo
  locales
  libicu74
)

main() {
  export DEBIAN_FRONTEND=noninteractive

  info "Updating apt package index"
  apt-get update

  info "Installing base packages: ${BASE_PACKAGES[*]}"
  apt-get install -y --no-install-recommends "${BASE_PACKAGES[@]}"

  info "Generating en_US.UTF-8 locale"
  locale-gen en_US.UTF-8

  info "Cleaning apt caches"
  apt-get clean
  rm -rf /var/lib/apt/lists/*

  info "Base install complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
