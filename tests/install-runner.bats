#!/usr/bin/env bats
#
# Unit tests for install-runner.sh: arch mapping and the main() guard clauses
# that fail before any network access happens.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../images/common/install-runner.sh"
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

# --- main() end-to-end against a faked download/install tree ------------------
#
# These exercise main() past the arch guard by stubbing out curl/tar/chown on
# PATH (no real network access or privileged chown) and pre-seeding a fake
# bin/installdependencies.sh, so we can assert on whether SKIP_INSTALLDEPS
# caused it to be invoked, and that ~/.runner-version is written regardless.
# Run via a real `bash -c` subprocess (not bats' `run` alone) so the script's
# own `set -euo pipefail` genuinely governs main(), same rationale as the
# guard-clause tests above.

# setup_fake_install_env populates $1 with stub curl/tar/chown executables
# and $2 (acting as RUNNER_HOME) with a pre-seeded bin/installdependencies.sh
# that records its own invocation, so main() never touches the network or a
# real "runner" system account.
setup_fake_install_env() {
  local fakebin="$1"
  local runner_home="$2"
  mkdir -p "${fakebin}" "${runner_home}/bin"

  cat >"${fakebin}/curl" <<'EOF'
#!/usr/bin/env bash
# Stub curl: writes an empty placeholder at the -o target. No network call.
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
: > "${out}"
EOF

  cat >"${fakebin}/tar" <<'EOF'
#!/usr/bin/env bash
# Stub tar: no-op. bin/installdependencies.sh is pre-seeded by the test
# instead of being extracted from a real tarball.
exit 0
EOF

  cat >"${fakebin}/chown" <<'EOF'
#!/usr/bin/env bash
# Stub chown: no-op. Avoids requiring a real "runner" system account/root.
exit 0
EOF

  chmod +x "${fakebin}/curl" "${fakebin}/tar" "${fakebin}/chown"

  cat >"${runner_home}/bin/installdependencies.sh" <<EOF
#!/usr/bin/env bash
printf 'called\n' >> "${runner_home}/installdependencies.called"
EOF
  chmod +x "${runner_home}/bin/installdependencies.sh"
}

@test "main skips ./bin/installdependencies.sh and logs why when SKIP_INSTALLDEPS=true" {
  local fakebin="${BATS_TEST_TMPDIR}/fakebin-skip-true"
  local runner_home="${BATS_TEST_TMPDIR}/runner-home-skip-true"
  setup_fake_install_env "${fakebin}" "${runner_home}"

  run bash -c "
    export PATH="${fakebin}:\${PATH}"
    export RUNNER_HOME='${runner_home}'
    export RUNNER_USER='runner'
    export RUNNER_VERSION='2.317.0'
    export SKIP_INSTALLDEPS=true
    source '${SCRIPT}'
    main
  "

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Skipping ./bin/installdependencies.sh (SKIP_INSTALLDEPS=true)"* ]]
  [ ! -f "${runner_home}/installdependencies.called" ]
  [ -f "${runner_home}/.runner-version" ]
  run cat "${runner_home}/.runner-version"
  [ "${output}" = "2.317.0" ]
}

@test "main calls ./bin/installdependencies.sh when SKIP_INSTALLDEPS=false" {
  local fakebin="${BATS_TEST_TMPDIR}/fakebin-skip-false"
  local runner_home="${BATS_TEST_TMPDIR}/runner-home-skip-false"
  setup_fake_install_env "${fakebin}" "${runner_home}"

  run bash -c "
    export PATH="${fakebin}:\${PATH}"
    export RUNNER_HOME='${runner_home}'
    export RUNNER_USER='runner'
    export RUNNER_VERSION='2.317.0'
    export SKIP_INSTALLDEPS=false
    source '${SCRIPT}'
    main
  "

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Installing runner dependencies"* ]]
  [[ "${output}" != *"Skipping ./bin/installdependencies.sh"* ]]
  [ -f "${runner_home}/installdependencies.called" ]
  [ -f "${runner_home}/.runner-version" ]
  run cat "${runner_home}/.runner-version"
  [ "${output}" = "2.317.0" ]
}

@test "main calls ./bin/installdependencies.sh when SKIP_INSTALLDEPS is unset" {
  local fakebin="${BATS_TEST_TMPDIR}/fakebin-skip-unset"
  local runner_home="${BATS_TEST_TMPDIR}/runner-home-skip-unset"
  setup_fake_install_env "${fakebin}" "${runner_home}"

  run bash -c "
    unset SKIP_INSTALLDEPS
    export PATH="${fakebin}:\${PATH}"
    export RUNNER_HOME='${runner_home}'
    export RUNNER_USER='runner'
    export RUNNER_VERSION='2.317.0'
    source '${SCRIPT}'
    main
  "

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Installing runner dependencies"* ]]
  [[ "${output}" != *"Skipping ./bin/installdependencies.sh"* ]]
  [ -f "${runner_home}/installdependencies.called" ]
  [ -f "${runner_home}/.runner-version" ]
  run cat "${runner_home}/.runner-version"
  [ "${output}" = "2.317.0" ]
}
