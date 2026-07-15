#!/usr/bin/env bash
#
# install-dotnet.sh - install the .NET SDK from the distro archive.
#
# Installs .NET packages from the distro archive. Intended to run as root during
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

# .NET packages to install via apt.
PACKAGES=(
  dotnet-sdk-8.0
)

main() {
  info "Installing .NET packages via apt"
  apt-get update
  apt-get install -y --no-install-recommends "${PACKAGES[@]}"
  rm -rf /var/lib/apt/lists/*

  info "Smoke checking .NET"
  # Set environment variables before running dotnet command
  export DOTNET_CLI_TELEMETRY_OPTOUT=1
  dotnet --list-sdks

  info ".NET install complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi