#!/usr/bin/env bash
#
# install-php.sh - install PHP CLI from the distro archive plus a pinned, checksum-verified Composer.
#
# Installs PHP packages from the distro archive and downloads Composer. Intended to run as root during
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

# PHP packages to install via apt.
PACKAGES=(
  php-cli
  php-curl
  php-mbstring
  php-xml
  php-zip
)

main() {
  local composer_version="${COMPOSER_VERSION:-}"

  if [[ -z "${composer_version}" ]]; then
    err "COMPOSER_VERSION is required"
    return 1
  fi

  info "Installing PHP packages via apt"
  apt-get update
  apt-get install -y --no-install-recommends "${PACKAGES[@]}"
  rm -rf /var/lib/apt/lists/*

  # Download and verify Composer
  local work_dir
  work_dir="$(mktemp -d)"
  cd "${work_dir}"

  info "Downloading Composer ${composer_version}"
  local url="https://getcomposer.org/download/${composer_version}/composer.phar"
  local sums_url="${url}.sha256sum"

  curl -fsSL -o composer.phar "${url}"
  curl -fsSL -o composer.phar.sha256sum "${sums_url}"

  info "Verifying Composer checksum"
  sha256sum -c composer.phar.sha256sum

  info "Installing Composer to /usr/local/bin"
  install -m 0755 composer.phar /usr/local/bin/composer

  info "Cleaning up"
  cd /
  rm -rf "${work_dir}"

  info "Smoke checking PHP and Composer"
  php --version
  COMPOSER_ALLOW_SUPERUSER=1 composer --version

  info "PHP install complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi