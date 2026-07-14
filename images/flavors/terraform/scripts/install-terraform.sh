#!/usr/bin/env bash
#
# install-terraform.sh - download, verify and install Terraform.
#
# Reads TERRAFORM_VERSION and TARGETARCH from the environment. Downloads the
# release zip and its SHA256SUMS from releases.hashicorp.com, verifies the
# zip's checksum, installs the binary into /usr/local/bin and runs a smoke
# check. Intended to run as root during the flavor image build.
#
# Baking Terraform into the image (rather than installing it at job time) keeps
# ephemeral runners fast and hermetic: no per-job download, no network flakiness
# mid-job, and a pinned, checksum-verified version.

set -euo pipefail

# The build copies helpers.sh next to this script under /tmp/scripts/, so it is
# sourced from SCRIPT_DIR at build time; the source= directive below points at
# its in-repo location for shellcheck.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=../../../common/helpers.sh
source "${SCRIPT_DIR}/helpers.sh"

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# map_arch maps a Docker TARGETARCH value to the Terraform release arch string.
# Terraform zips use amd64/arm64 naming directly (unlike the runner's x64).
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
  local terraform_version="${TERRAFORM_VERSION:-}"
  local target_arch="${TARGETARCH:-amd64}"

  if [[ -z "${terraform_version}" ]]; then
    err "TERRAFORM_VERSION is required"
    return 1
  fi

  local arch
  arch="$(map_arch "${target_arch}")"

  local zip="terraform_${terraform_version}_linux_${arch}.zip"
  local base_url="https://releases.hashicorp.com/terraform/${terraform_version}"
  local url="${base_url}/${zip}"
  local sums="terraform_${terraform_version}_SHA256SUMS"
  local sums_url="${base_url}/${sums}"

  local work_dir
  work_dir="$(mktemp -d)"
  cd "${work_dir}"

  info "Downloading ${url}"
  curl -fsSL -o "${zip}" "${url}"

  info "Downloading ${sums_url}"
  curl -fsSL -o "${sums}" "${sums_url}"

  info "Verifying ${zip} checksum"
  # Verify only the line for the zip we fetched; sha256sum -c fails if the file
  # is missing or the digest does not match.
  grep " ${zip}\$" "${sums}" | sha256sum -c -

  info "Installing terraform into ${INSTALL_DIR}"
  unzip -o "${zip}" terraform -d "${INSTALL_DIR}"
  chmod 0755 "${INSTALL_DIR}/terraform"

  info "Cleaning up"
  cd /
  rm -rf "${work_dir}"

  info "Smoke checking terraform"
  terraform version

  info "Terraform install complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
