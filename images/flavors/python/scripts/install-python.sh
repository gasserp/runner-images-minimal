#!/usr/bin/env bash
#
# install-python.sh - install Python 3 with pip and venv via apt.
#
# Installs Python packages from the distro archive. Intended to run as root during
# the flavor image build.
#
# Requires an apt-based (ubuntu) base image.

set -euo pipefail

# The build copies helpers.sh next to this script under /tmp/scripts/, so it is
# sourced from SCRIPT_DIR at build time; the source= directive below points at
# its in-repo location for shellcheck.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../../../common/helpers.sh
source "${SCRIPT_DIR}/helpers.sh"

# Python packages to install via apt.
PACKAGES=(
  python3
  python3-pip
  python3-venv
)

main() {
  info "Installing Python packages via apt"
  apt-get update
  apt-get install -y --no-install-recommends "${PACKAGES[@]}"
  rm -rf /var/lib/apt/lists/*

  info "Smoke checking Python"
  python3 --version
  pip3 --version

  info "Python install complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi