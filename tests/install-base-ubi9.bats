#!/usr/bin/env bats
#
# Unit tests for images/ubi9/scripts/install-base.sh (microdnf-based). Shares
# baseline assertions with install-base-ubuntu.bats via
# lib/install-base-common.bash.

load 'lib/install-base-common'

setup() {
  install_base_setup ubi9
}

@test "[ubi9] BASE_PACKAGES is a non-empty array" {
  assert_base_packages_nonempty
}

@test "[ubi9] BASE_PACKAGES includes the tools required at runtime" {
  # curl is omitted: ubi9-minimal ships curl-minimal, which provides the curl
  # binary, and the full curl package conflicts with it.
  assert_base_packages_includes_runtime_tools git jq tar unzip sudo ca-certificates
}

@test "[ubi9] BASE_PACKAGES does not include curl (conflicts with preinstalled curl-minimal)" {
  ! assert_base_packages_contains curl
}

@test "[ubi9] BASE_PACKAGES has no duplicate entries" {
  assert_base_packages_no_duplicates
}

@test "[ubi9] BASE_PACKAGES includes the .NET runtime deps normally provided by installdependencies.sh" {
  local dep
  for dep in libicu krb5-libs openssl-libs zlib; do
    assert_base_packages_contains "${dep}"
  done
}

@test "[ubi9] lttng-ust is attempted as an optional best-effort package" {
  local found=0 pkg
  for pkg in "${OPTIONAL_PACKAGES[@]}"; do
    [[ "${pkg}" == "lttng-ust" ]] && found=1
  done
  [ "${found}" -eq 1 ]
}
