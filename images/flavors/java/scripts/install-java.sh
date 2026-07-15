#!/usr/bin/env bash
#
# install-java.sh - install OpenJDK 21 and Maven via apt.
#
# Installs Java packages from the distro archive. Intended to run as root during
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

# Java packages to install via apt.
PACKAGES=(
  openjdk-21-jdk-headless
  maven
)

main() {
  info "Installing Java packages via apt"
  apt-get update
  apt-get install -y --no-install-recommends "${PACKAGES[@]}"
  rm -rf /var/lib/apt/lists/*

  info "Smoke checking Java"
  java -version
  mvn -version

  info "Java install complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi