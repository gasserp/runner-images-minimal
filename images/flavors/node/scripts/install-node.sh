#!/usr/bin/env bash
#
# install-node.sh - download, verify and install Node.js.
#
# Reads NODE_VERSION and TARGETARCH from the environment. Downloads the
# release tarball and its SHASUMS256.txt from nodejs.org, verifies the
# tarball's checksum, installs the binary into /usr/local/node and symlinks
# the tools into /usr/local/bin, and runs a smoke check. Intended to run as
# root during the flavor image build.
#
# Baking Node.js into the image (rather than installing it at job time) keeps
# ephemeral runners fast and hermetic: no per-job download, no network flakiness
# mid-job, and a pinned, checksum-verified version.

set -euo pipefail

# The build copies helpers.sh next to this script under /tmp/scripts/, so it is
# sourced from SCRIPT_DIR at build time; the source= directive below points at
# its in-repo location for shellcheck.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../../../common/helpers.sh
source "${SCRIPT_DIR}/helpers.sh"

# map_arch maps a Docker TARGETARCH value to the Node.js release arch string.
# Node.js tarballs use x64/arm64 naming directly (unlike the runner's x64).
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
  local node_version="${NODE_VERSION:-}"
  local target_arch="${TARGETARCH:-amd64}"

  if [[ -z "${node_version}" ]]; then
    err "NODE_VERSION is required"
    return 1
  fi

  local arch
  arch="$(map_arch "${target_arch}")"

  local tarball="node-v${node_version}-linux-${arch}.tar.gz"
  local base_url="https://nodejs.org/dist/v${node_version}"
  local url="${base_url}/${tarball}"
  local sums="SHASUMS256.txt"
  local sums_url="${base_url}/${sums}"

  local work_dir
  work_dir="$(mktemp -d)"
  cd "${work_dir}"

  info "Downloading ${url}"
  curl -fsSL -o "${tarball}" "${url}"

  info "Downloading ${sums_url}"
  curl -fsSL -o "${sums}" "${sums_url}"

  info "Verifying ${tarball} checksum"
  # Verify only the line for the tarball we fetched; sha256sum -c fails if the file
  # is missing or the digest does not match.
  grep " ${tarball}\$" "${sums}" | sha256sum -c -

  info "Installing node into /usr/local/node"
  local NODE_DIR="${NODE_DIR:-/usr/local/node}"
  local BIN_DIR="${BIN_DIR:-/usr/local/bin}"
  mkdir -p "${NODE_DIR}"
  tar -xzf "${tarball}" -C "${NODE_DIR}" --strip-components=1

  info "Creating symlinks for node, npm, npx and corepack"
  for tool in node npm npx corepack; do
    ln -sf "${NODE_DIR}/bin/${tool}" "${BIN_DIR}/${tool}"
  done

  info "Cleaning up"
  cd /
  rm -rf "${work_dir}"

  info "Smoke checking node"
  node --version

  info "Smoke checking npm"
  npm --version

  info "Node.js install complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi