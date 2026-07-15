#!/usr/bin/env bash
#
# install-go.sh - download, verify and install Go.
#
# Reads GO_VERSION and TARGETARCH from the environment. Downloads the
# release tarball and its .sha256 checksum from dl.google.com, verifies the
# tarball's checksum, installs the binary into /usr/local/go and symlinks
# the tools into /usr/local/bin, and runs a smoke check. Intended to run as
# root during the flavor image build.
#
# Baking Go into the image (rather than installing it at job time) keeps
# ephemeral runners fast and hermetic: no per-job download, no network flakiness
# mid-job, and a pinned, checksum-verified version.

set -euo pipefail

# The build copies helpers.sh next to this script under /tmp/scripts/, so it is
# sourced from SCRIPT_DIR at build time; the source= directive below points at
# its in-repo location for shellcheck.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../../../common/helpers.sh
source "${SCRIPT_DIR}/helpers.sh"

# map_arch maps a Docker TARGETARCH value to the Go release arch string.
# Go tarballs use amd64/arm64 naming directly (same as terraform).
# Pure function so it can be unit tested by sourcing this file.
map_arch() {
  local target_arch="$1"
  case "${target_arch}" in
    amd64 | x64 | x86_64)
      printf 'amd64'
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
  local go_version="${GO_VERSION:-}"
  local target_arch="${TARGETARCH:-amd64}"

  if [[ -z "${go_version}" ]]; then
    err "GO_VERSION is required"
    return 1
  fi

  local arch
  arch="$(map_arch "${target_arch}")"

  local tarball="go${go_version}.linux-${arch}.tar.gz"
  local url="https://dl.google.com/go/${tarball}"
  local sums="${tarball}.sha256"
  local sums_url="${url}.sha256"

  local work_dir
  work_dir="$(mktemp -d)"
  cd "${work_dir}"

  info "Downloading ${url}"
  curl -fsSL -o "${tarball}" "${url}"

  info "Downloading ${sums_url}"
  curl -fsSL -o "${sums}" "${sums_url}"

  info "Verifying ${tarball} checksum"
  # The .sha256 file may contain just the bare hash, so we need to format it
  # properly for sha256sum -c
  local hash
  hash="$(awk '{print $1}' "${sums}")"
  printf '%s  %s\n' "${hash}" "${tarball}" | sha256sum -c -

  info "Installing go into /usr/local"
  local GO_ROOT_PARENT="${GO_ROOT_PARENT:-/usr/local}"
  local BIN_DIR="${BIN_DIR:-/usr/local/bin}"
  rm -rf "${GO_ROOT_PARENT}/go"
  tar -C "${GO_ROOT_PARENT}" -xzf "${tarball}"

  info "Creating symlinks for go and gofmt"
  for tool in go gofmt; do
    ln -sf "${GO_ROOT_PARENT}/go/bin/${tool}" "${BIN_DIR}/${tool}"
  done

  info "Cleaning up"
  cd /
  rm -rf "${work_dir}"

  info "Smoke checking go"
  go version

  info "Go install complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi