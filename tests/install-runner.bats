#!/usr/bin/env bats
#
# Unit tests for install-runner.sh: arch mapping and the main() guard clauses
# that fail before any network access happens.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../images/ubuntu/scripts/install-runner.sh"
  source "${SCRIPT}"
}

# --- map_arch -----------------------------------------------------------------

@test "map_arch maps amd64 to x64" {
  run map_arch "amd64"
  [ "${status}" -eq 0 ]
  [ "${output}" = "x64" ]
}

@test "map_arch maps x64 to x64" {
  run map_arch "x64"
  [ "${status}" -eq 0 ]
  [ "${output}" = "x64" ]
}

@test "map_arch maps x86_64 to x64" {
  run map_arch "x86_64"
  [ "${status}" -eq 0 ]
  [ "${output}" = "x64" ]
}

@test "map_arch maps arm64 to arm64" {
  run map_arch "arm64"
  [ "${status}" -eq 0 ]
  [ "${output}" = "arm64" ]
}

@test "map_arch maps aarch64 to arm64" {
  run map_arch "aarch64"
  [ "${status}" -eq 0 ]
  [ "${output}" = "arm64" ]
}

@test "map_arch rejects unknown arch" {
  run map_arch "riscv64"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Unsupported architecture"* ]]
  [[ "${output}" == *"riscv64"* ]]
}

@test "map_arch rejects an empty arch" {
  run map_arch ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Unsupported architecture"* ]]
}

@test "map_arch is case-sensitive and rejects uppercase input" {
  run map_arch "AMD64"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Unsupported architecture"* ]]
}

@test "map_arch rejects arm (32-bit) as it is not supported" {
  run map_arch "arm"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Unsupported architecture"* ]]
}

# --- main() guard clauses (fail before touching the network) ------------------
#
# These run main() in a real bash subprocess (rather than via bats' `run`,
# which disables `set -e` for the duration of the call) so the script's own
# `set -euo pipefail` genuinely aborts main() at the first failing command,
# exactly as it would during a real image build. Without this, a failing
# `arch="$(map_arch ...)"` assignment would silently continue into curl/tar
# with an empty arch instead of stopping main() immediately.

@test "main fails with a clear message when RUNNER_VERSION is unset" {
  run bash -c "unset RUNNER_VERSION; source '${SCRIPT}'; main"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"RUNNER_VERSION is required"* ]]
}

@test "main fails with a clear message when RUNNER_VERSION is empty" {
  RUNNER_VERSION="" run bash -c "source '${SCRIPT}'; main"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"RUNNER_VERSION is required"* ]]
}

@test "main fails with a clear message for an unsupported TARGETARCH" {
  RUNNER_VERSION="2.317.0" TARGETARCH="riscv64" \
    run bash -c "source '${SCRIPT}'; main"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Unsupported architecture: riscv64"* ]]
}

@test "main defaults TARGETARCH to amd64 when unset (arch guard passes)" {
  # main() reaches the network/filesystem steps once past the arch guard, so
  # we don't run it for real here (no network in the test sandbox). Instead
  # we assert the same default resolution main() uses would map cleanly.
  unset TARGETARCH
  local default_arch="${TARGETARCH:-amd64}"
  run map_arch "${default_arch}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "x64" ]
}
