#!/usr/bin/env bats
#
# Unit tests for the pure functions in entrypoint.sh, plus a handful of
# mocked end-to-end tests that exercise main() against fake config.sh/run.sh
# binaries so we can assert on the exact arguments passed to the runner.

setup() {
  ENTRYPOINT="${BATS_TEST_DIRNAME}/../images/common/entrypoint.sh"
  # Sourcing is safe: the main guard prevents execution.
  source "${ENTRYPOINT}"
}

# --- resolve_labels ---------------------------------------------------------

@test "resolve_labels returns default when empty" {
  run resolve_labels ""
  [ "${status}" -eq 0 ]
  [ "${output}" = "self-hosted,linux,minimal" ]
}

@test "resolve_labels returns default when unset (no argument)" {
  run resolve_labels
  [ "${status}" -eq 0 ]
  [ "${output}" = "self-hosted,linux,minimal" ]
}

@test "resolve_labels returns provided labels" {
  run resolve_labels "gpu,large"
  [ "${status}" -eq 0 ]
  [ "${output}" = "gpu,large" ]
}

@test "resolve_labels passes through a single label unchanged" {
  run resolve_labels "gpu"
  [ "${status}" -eq 0 ]
  [ "${output}" = "gpu" ]
}

@test "resolve_labels does not treat whitespace as empty" {
  run resolve_labels " "
  [ "${status}" -eq 0 ]
  [ "${output}" = " " ]
}

# --- validate_env ------------------------------------------------------------

@test "validate_env fails without repo url" {
  run validate_env "" "tok"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"RUNNER_REPO_URL is required"* ]]
}

@test "validate_env fails without token" {
  run validate_env "https://github.com/o/r" ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"RUNNER_TOKEN is required"* ]]
}

@test "validate_env fails without either argument" {
  run validate_env "" ""
  [ "${status}" -ne 0 ]
}

@test "validate_env reports only the repo url error when both are missing" {
  # The function returns on the first failure, so only the RUNNER_REPO_URL
  # message should be emitted, not the RUNNER_TOKEN one too.
  run validate_env "" ""
  [[ "${output}" == *"RUNNER_REPO_URL is required"* ]]
  [[ "${output}" != *"RUNNER_TOKEN is required"* ]]
}

@test "validate_env passes with both" {
  run validate_env "https://github.com/o/r" "tok"
  [ "${status}" -eq 0 ]
}

@test "validate_env passes with no explicit arguments treated as empty" {
  run validate_env
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"RUNNER_REPO_URL is required"* ]]
}

# --- build_config_args -------------------------------------------------------

@test "build_config_args includes core flags" {
  run build_config_args "https://github.com/o/r" "tok" "myname" "a,b" "_work" "false"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--unattended"* ]]
  [[ "${output}" == *"https://github.com/o/r"* ]]
  [[ "${output}" == *"myname"* ]]
  [[ "${output}" == *"--replace"* ]]
  [[ "${output}" != *"--ephemeral"* ]]
}

@test "build_config_args propagates a custom RUNNER_NAME" {
  run build_config_args "https://github.com/o/r" "tok" "custom-runner-name" "a,b" "_work" "false"
  [ "${status}" -eq 0 ]
  # Assert --name is immediately followed by the custom name (adjacent lines).
  [[ "${output}" == *$'--name\ncustom-runner-name'* ]]
}

@test "build_config_args propagates a custom RUNNER_WORK_DIR" {
  run build_config_args "https://github.com/o/r" "tok" "myname" "a,b" "/custom/work/dir" "false"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'--work\n/custom/work/dir'* ]]
}

@test "build_config_args propagates custom labels" {
  run build_config_args "https://github.com/o/r" "tok" "myname" "gpu,large,self-hosted" "_work" "false"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'--labels\ngpu,large,self-hosted'* ]]
}

@test "build_config_args omits --ephemeral when the flag is false" {
  run build_config_args "https://github.com/o/r" "tok" "myname" "a,b" "_work" "false"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"--ephemeral"* ]]
}

@test "build_config_args omits --ephemeral for any non-'true' value" {
  run build_config_args "https://github.com/o/r" "tok" "myname" "a,b" "_work" "yes"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"--ephemeral"* ]]
}

@test "build_config_args adds ephemeral when requested" {
  run build_config_args "https://github.com/o/r" "tok" "myname" "a,b" "_work" "true"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--ephemeral"* ]]
}

@test "build_config_args always includes --replace to survive re-registration" {
  run build_config_args "https://github.com/o/r" "tok" "myname" "a,b" "_work" "true"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--replace"* ]]
}

# --- deregister ---------------------------------------------------------------

@test "deregister invokes config.sh remove with the token" {
  local workdir="${BATS_TEST_TMPDIR}/deregister"
  mkdir -p "${workdir}"
  cat >"${workdir}/config.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$(dirname "$0")/remove.args"
exit 0
EOF
  chmod +x "${workdir}/config.sh"

  ( cd "${workdir}" && deregister "secret-token" )

  run cat "${workdir}/remove.args"
  [[ "${output}" == *"remove"* ]]
  [[ "${output}" == *"secret-token"* ]]
}

@test "deregister does not abort when config.sh remove fails" {
  local workdir="${BATS_TEST_TMPDIR}/deregister-fail"
  mkdir -p "${workdir}"
  cat >"${workdir}/config.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${workdir}/config.sh"

  run bash -c "cd '${workdir}' && source '${ENTRYPOINT}' && deregister 'tok'"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARN: failed to remove runner registration"* ]]
}

# --- shutdown ------------------------------------------------------------------

@test "shutdown stops the runner process before deregistering" {
  local workdir="${BATS_TEST_TMPDIR}/shutdown"
  mkdir -p "${workdir}"
  cat >"${workdir}/config.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$(dirname "$0")/remove.args"
exit 0
EOF
  chmod +x "${workdir}/config.sh"

  # Start a long-lived stand-in for run.sh directly, so $! is the sleep
  # process itself and not a wrapper subshell. Keep it short: if shutdown
  # fails to kill it, the wait below returns 0 after 5s instead of hanging.
  sleep 5 &
  local pid=$!

  ( cd "${workdir}" && shutdown "tok" "${pid}" )

  # Reap the child; exit status 143 (128+SIGTERM) proves shutdown killed it.
  local wait_status=0
  wait "${pid}" || wait_status=$?
  [ "${wait_status}" -eq 143 ]
  run cat "${workdir}/remove.args"
  [[ "${output}" == *"remove"* ]]
  [[ "${output}" == *"tok"* ]]
}

@test "shutdown still deregisters when no runner process is given" {
  local workdir="${BATS_TEST_TMPDIR}/shutdown-nopid"
  mkdir -p "${workdir}"
  cat >"${workdir}/config.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$(dirname "$0")/remove.args"
exit 0
EOF
  chmod +x "${workdir}/config.sh"

  ( cd "${workdir}" && shutdown "tok" "" )

  run cat "${workdir}/remove.args"
  [[ "${output}" == *"remove"* ]]
}

# --- main() end-to-end, against mocked config.sh / run.sh --------------------
#
# These tests exercise the real main() function with fake config.sh / run.sh
# executables so we can assert on the arguments the entrypoint actually
# passes through, and on its fail-fast behaviour when required env vars are
# missing.

setup_mock_runner_dir() {
  local dir="$1"
  mkdir -p "${dir}"
  cat >"${dir}/config.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$(dirname "$0")/config.args"
exit 0
EOF
  cat >"${dir}/run.sh" <<'EOF'
#!/usr/bin/env bash
# Simulate a runner job loop that finishes immediately.
exit 0
EOF
  chmod +x "${dir}/config.sh" "${dir}/run.sh"
}

@test "main fails fast with a clear message when RUNNER_REPO_URL is missing" {
  local workdir="${BATS_TEST_TMPDIR}/main-missing-url"
  setup_mock_runner_dir "${workdir}"

  RUNNER_TOKEN="tok" run bash -c "cd '${workdir}' && bash '${ENTRYPOINT}'"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"RUNNER_REPO_URL is required"* ]]
  [ ! -f "${workdir}/config.args" ]
}

@test "main fails fast with a clear message when RUNNER_TOKEN is missing" {
  local workdir="${BATS_TEST_TMPDIR}/main-missing-token"
  setup_mock_runner_dir "${workdir}"

  RUNNER_REPO_URL="https://github.com/o/r" \
    run bash -c "cd '${workdir}' && bash '${ENTRYPOINT}'"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"RUNNER_TOKEN is required"* ]]
  [ ! -f "${workdir}/config.args" ]
}

@test "main propagates custom RUNNER_NAME, RUNNER_WORK_DIR and RUNNER_EPHEMERAL to config.sh" {
  local workdir="${BATS_TEST_TMPDIR}/main-custom"
  setup_mock_runner_dir "${workdir}"

  RUNNER_REPO_URL="https://github.com/o/r" \
    RUNNER_TOKEN="tok" \
    RUNNER_NAME="custom-runner-name" \
    RUNNER_WORK_DIR="/custom/work/dir" \
    RUNNER_EPHEMERAL="true" \
    run bash -c "cd '${workdir}' && bash '${ENTRYPOINT}'"

  [ "${status}" -eq 0 ]
  run cat "${workdir}/config.args"
  [[ "${output}" == *"custom-runner-name"* ]]
  [[ "${output}" == *"/custom/work/dir"* ]]
  [[ "${output}" == *"--ephemeral"* ]]
}

@test "main defaults RUNNER_NAME to the container hostname when unset" {
  local workdir="${BATS_TEST_TMPDIR}/main-default-name"
  setup_mock_runner_dir "${workdir}"

  # GitHub-hosted CI runners export RUNNER_NAME (and other RUNNER_* vars)
  # into every job, so default-behaviour tests must unset them explicitly.
  RUNNER_REPO_URL="https://github.com/o/r" \
    RUNNER_TOKEN="tok" \
    run bash -c "unset RUNNER_NAME RUNNER_LABELS RUNNER_WORK_DIR RUNNER_EPHEMERAL
      cd '${workdir}' && bash '${ENTRYPOINT}'"

  [ "${status}" -eq 0 ]
  local expected_name
  expected_name="$(hostname)"
  run cat "${workdir}/config.args"
  [[ "${output}" == *"${expected_name}"* ]]
}

@test "main defaults RUNNER_WORK_DIR to _work and omits --ephemeral when unset" {
  local workdir="${BATS_TEST_TMPDIR}/main-default-work"
  setup_mock_runner_dir "${workdir}"

  # Unset ambient RUNNER_* vars exported by GitHub-hosted CI runners.
  RUNNER_REPO_URL="https://github.com/o/r" \
    RUNNER_TOKEN="tok" \
    run bash -c "unset RUNNER_NAME RUNNER_LABELS RUNNER_WORK_DIR RUNNER_EPHEMERAL
      cd '${workdir}' && bash '${ENTRYPOINT}'"

  [ "${status}" -eq 0 ]
  run cat "${workdir}/config.args"
  [[ "${output}" == *$'--work\n_work'* ]]
  [[ "${output}" != *"--ephemeral"* ]]
}

@test "main falls back to default labels when RUNNER_LABELS is empty" {
  local workdir="${BATS_TEST_TMPDIR}/main-empty-labels"
  setup_mock_runner_dir "${workdir}"

  RUNNER_REPO_URL="https://github.com/o/r" \
    RUNNER_TOKEN="tok" \
    RUNNER_LABELS="" \
    run bash -c "cd '${workdir}' && bash '${ENTRYPOINT}'"

  [ "${status}" -eq 0 ]
  run cat "${workdir}/config.args"
  [[ "${output}" == *"self-hosted,linux,minimal"* ]]
}
