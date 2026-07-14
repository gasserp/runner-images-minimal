#!/usr/bin/env bats
#
# Unit tests for install-base.sh. main() itself calls apt-get and is not
# exercised here (that's the image build's job); instead we assert on the
# declarative BASE_PACKAGES list that drives it, since a missing entry there
# would silently break the built image (e.g. validate-image.sh's binary
# checks).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../images/ubuntu/scripts/install-base.sh"
  source "${SCRIPT}"
}

@test "BASE_PACKAGES is a non-empty array" {
  [ "${#BASE_PACKAGES[@]}" -gt 0 ]
}

@test "BASE_PACKAGES includes the tools required at runtime" {
  local pkg required=(git curl jq tar unzip sudo ca-certificates)
  for pkg in "${required[@]}"; do
    local found=0
    local candidate
    for candidate in "${BASE_PACKAGES[@]}"; do
      [[ "${candidate}" == "${pkg}" ]] && found=1 && break
    done
    [ "${found}" -eq 1 ]
  done
}

@test "BASE_PACKAGES has no duplicate entries" {
  local seen=() pkg
  for pkg in "${BASE_PACKAGES[@]}"; do
    local dup=0 s
    for s in "${seen[@]}"; do
      [[ "${s}" == "${pkg}" ]] && dup=1 && break
    done
    [ "${dup}" -eq 0 ]
    seen+=("${pkg}")
  done
}
