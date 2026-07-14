#!/usr/bin/env bash
#
# install-base.sh - install the minimal base packages needed by the runner on
# ubi9-minimal (microdnf).
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
# ubi9-minimal ships bash already; shadow-utils provides useradd (needed to
# create the runner user after this script runs) and glibc-langpack-en provides
# the en_US.UTF-8 locale.
#
# ubi9-minimal has no yum/dnf, so the runner's own ./bin/installdependencies.sh
# cannot run (install-runner.sh is invoked with SKIP_INSTALLDEPS=true). The
# .NET runtime dependencies it would otherwise install are added explicitly
# here: libicu krb5-libs openssl-libs zlib (and lttng-ust, see below).
#
# curl is intentionally absent: ubi9-minimal ships curl-minimal, which already
# provides /usr/bin/curl, and installing the full curl package conflicts with
# it (requires --allowerasing to swap).
BASE_PACKAGES=(
  ca-certificates
  git
  jq
  tar
  unzip
  gzip
  sudo
  shadow-utils
  findutils
  which
  glibc-langpack-en
  libicu
  krb5-libs
  openssl-libs
  zlib
)

# lttng-ust only provides optional .NET tracing support and may be missing
# from the freely available UBI repos (it lives in RHEL's full repos), so it
# is installed best-effort instead of failing the build.
OPTIONAL_PACKAGES=(
  lttng-ust
)

main() {
  info "Installing base packages: ${BASE_PACKAGES[*]}"
  microdnf install -y --nodocs "${BASE_PACKAGES[@]}"

  local pkg
  for pkg in "${OPTIONAL_PACKAGES[@]}"; do
    if microdnf install -y --nodocs "${pkg}"; then
      info "Installed optional package ${pkg}"
    else
      info "Optional package ${pkg} unavailable in the enabled repos; skipping"
    fi
  done

  info "Cleaning microdnf caches"
  microdnf clean all

  info "Base install complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
