#!/usr/bin/env bash
#
# install-rust.sh - download, verify and install Rust toolchain.
#
# Reads RUST_VERSION and TARGETARCH from the environment. Downloads the
# release tarball and its SHA256SUMS from static.rust-lang.org, verifies the
# tarball's checksum, installs the toolchain into /usr/local and runs a smoke
# check. Intended to run as root during the flavor image build.
#
# Baking Rust into the image (rather than installing it at job time) keeps
# ephemeral runners fast and hermetic: no per-job download, no network flakiness
# mid-job, and a pinned, checksum-verified version.

set -euo pipefail

# The build copies helpers.sh next to this script under /tmp/scripts/, so it is
# sourced from SCRIPT_DIR at build time; the source= directive below points at
# its in-repo location for shellcheck.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../../../common/helpers.sh
source "${SCRIPT_DIR}/helpers.sh"

# map_arch maps a Docker TARGETARCH value to the Rust target triple.
# Pure function so it can be unit tested by sourcing this file.
map_arch() {
  local target_arch="$1"
  case "${target_arch}" in
    amd64 | x64 | x86_64)
      printf 'x86_64-unknown-linux-gnu'
      ;;
    arm64 | aarch64)
      printf 'aarch64-unknown-linux-gnu'
      ;;
    *)
      err "Unsupported architecture: ${target_arch}"
      return 1
      ;;
  esac
}

main() {
  local rust_version="${RUST_VERSION:-}"
  local target_arch="${TARGETARCH:-amd64}"

  if [[ -z "${rust_version}" ]]; then
    err "RUST_VERSION is required"
    return 1
  fi

  # Install the C linker cargo needs at build/link time
  info "Installing gcc (linker for cargo builds)"
  apt-get update
  apt-get install -y --no-install-recommends gcc libc6-dev
  rm -rf /var/lib/apt/lists/*

  local triple
  triple="$(map_arch "${target_arch}")"

  local tarball="rust-${rust_version}-${triple}.tar.gz"
  local url="https://static.rust-lang.org/dist/${tarball}"
  local sums_url="${url}.sha256"

  local work_dir
  work_dir="$(mktemp -d)"
  cd "${work_dir}"

  info "Downloading ${url}"
  curl -fsSL -o "${tarball}" "${url}"

  info "Downloading ${sums_url}"
  curl -fsSL -o "${tarball}.sha256" "${sums_url}"

  info "Verifying ${tarball} checksum"
  local hash
  hash="$(awk '{print $1}' "${tarball}.sha256")"
  printf '%s  %s\n' "${hash}" "${tarball}" | sha256sum -c -

  info "Installing Rust toolchain"
  tar -xzf "${tarball}"
  "./rust-${rust_version}-${triple}/install.sh" --prefix="${INSTALL_PREFIX:-/usr/local}" --without=rust-docs

  info "Cleaning up"
  cd /
  rm -rf "${work_dir}"

  info "Smoke checking rustc and cargo"
  rustc --version
  cargo --version

  info "Rust install complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi