#!/usr/bin/env bash
#
# install-base.sh - install the minimal base packages needed by the runner.
#
# Idempotent: re-running only reinstalls already-present packages. Intended to
# run as root during the image build.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=helpers.sh
source "${SCRIPT_DIR}/helpers.sh"

# Packages kept deliberately small: just enough to fetch, verify and run the
# GitHub Actions runner plus common toolchain expectations (git, jq, sudo).
BASE_PACKAGES=(
  ca-certificates
  curl
  git
  jq
  tar
  unzip
  sudo
  locales
  gnupg
  lsb-release
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
