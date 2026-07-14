#!/usr/bin/env bats
#
# Unit tests for images/ubuntu/scripts/install-base.sh (apt-based). Shares
# baseline assertions with install-base-ubi9.bats via
# lib/install-base-common.bash.

load 'lib/install-base-common'

setup() {
  install_base_setup ubuntu
}

@test "[ubuntu] BASE_PACKAGES is a non-empty array" {
  assert_base_packages_nonempty
}

@test "[ubuntu] BASE_PACKAGES includes the tools required at runtime" {
  assert_base_packages_includes_runtime_tools git curl jq tar unzip sudo ca-certificates
}

@test "[ubuntu] BASE_PACKAGES has no duplicate entries" {
  assert_base_packages_no_duplicates
}

@test "[ubuntu] BASE_PACKAGES no longer includes gnupg" {
  ! assert_base_packages_contains gnupg
}

@test "[ubuntu] BASE_PACKAGES no longer includes lsb-release" {
  ! assert_base_packages_contains lsb-release
}
