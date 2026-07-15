#!/usr/bin/env bash
#
# install-dart.sh - download, verify and install Dart SDK.
#
# Reads DART_VERSION and TARGETARCH from the environment. Downloads the
# release zip and its .sha256sum file from storage.googleapis.com, verifies the
# zip's checksum, unpacks the SDK into /usr/local/dart-sdk (symlinking dart into /usr/local/bin) and runs a smoke check. Intended to run as root during the flavor image build.
#
# Baking Dart into the image (rather than installing it at job time) keeps
# ephemeral runners fast and hermetic: no per-job download, no network flakiness
# mid-job, and a pinned, checksum-verified version.

set -euo pipefail

# The build copies helpers.sh next to this script under /tmp/scripts/, so it is
# sourced from SCRIPT_DIR at build time; the source= directive below points at
# its in-repo location for shellcheck.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../../../common/helpers.sh
source "${SCRIPT_DIR}/helpers.sh"

# map_arch maps a Docker TARGETARCH value to the Dart SDK arch string.
# Dart SDK zips use x64/arm64 naming directly.
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
  local dart_version="${DART_VERSION:-}"
  local target_arch="${TARGETARCH:-amd64}"

  if [[ -z "${dart_version}" ]]; then
    err "DART_VERSION is required"
    return 1
  fi

  local arch
  arch="$(map_arch "${target_arch}")"

  local zip="dartsdk-linux-${arch}-release.zip"
  local url="https://storage.googleapis.com/dart-archive/channels/stable/release/${dart_version}/sdk/${zip}"
  local sums_url="${url}.sha256sum"

  local work_dir
  work_dir="$(mktemp -d)"
  cd "${work_dir}"

  info "Downloading ${url}"
  curl -fsSL -o "${zip}" "${url}"

  info "Downloading ${sums_url}"
  curl -fsSL -o "${zip}.sha256sum" "${sums_url}"

  info "Verifying ${zip} checksum"
  sha256sum -c "${zip}.sha256sum"

  info "Installing Dart SDK"
  local SDK_PARENT="${SDK_PARENT:-/usr/local}"
  local BIN_DIR="${BIN_DIR:-/usr/local/bin}"
  rm -rf "${SDK_PARENT}/dart-sdk"
  unzip -q "${zip}" -d "${SDK_PARENT}"
  ln -sf "${SDK_PARENT}/dart-sdk/bin/dart" "${BIN_DIR}/dart"

  info "Cleaning up"
  cd /
  rm -rf "${work_dir}"

  info "Smoke checking dart"
  dart --version

  info "Dart install complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi