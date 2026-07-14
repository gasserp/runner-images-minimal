#!/usr/bin/env bash
#
# entrypoint.sh - configure and run the GitHub Actions runner.
#
# Runs as the `runner` user. Registers the runner against a repository (or org)
# using a short-lived registration token, then runs it in the foreground.
# On SIGTERM/SIGINT it deregisters cleanly before exiting.
#
# Required env vars:
#   RUNNER_REPO_URL  - e.g. https://github.com/owner/repo
#   RUNNER_TOKEN     - registration token
#
# Optional env vars:
#   RUNNER_NAME      - runner name          (default: hostname)
#   RUNNER_LABELS    - comma separated      (default: self-hosted,linux,minimal)
#   RUNNER_WORK_DIR  - work directory       (default: _work)
#   RUNNER_EPHEMERAL - "true" to add --ephemeral

set -euo pipefail

# Default labels applied when RUNNER_LABELS is unset or empty.
readonly DEFAULT_LABELS="self-hosted,linux,minimal"

# resolve_labels echoes the labels to use: the provided value, or the default
# when empty. Pure function for testability.
resolve_labels() {
  local labels="${1:-}"
  if [[ -z "${labels}" ]]; then
    printf '%s' "${DEFAULT_LABELS}"
  else
    printf '%s' "${labels}"
  fi
}

# validate_env checks that the required variables are set, printing a clear
# message and returning non-zero for the first missing one.
validate_env() {
  local repo_url="${1:-}"
  local token="${2:-}"

  if [[ -z "${repo_url}" ]]; then
    printf 'ERROR: RUNNER_REPO_URL is required (e.g. https://github.com/owner/repo)\n' >&2
    return 1
  fi
  if [[ -z "${token}" ]]; then
    printf 'ERROR: RUNNER_TOKEN is required (a runner registration token)\n' >&2
    return 1
  fi
}

# build_config_args assembles the argument list for ./config.sh on stdout,
# one argument per line, from explicit parameters. Pure function for testing.
#   $1 repo_url  $2 token  $3 name  $4 labels  $5 work_dir  $6 ephemeral
build_config_args() {
  local repo_url="$1"
  local token="$2"
  local name="$3"
  local labels="$4"
  local work_dir="$5"
  local ephemeral="$6"

  printf '%s\n' \
    --unattended \
    --url "${repo_url}" \
    --token "${token}" \
    --name "${name}" \
    --labels "${labels}" \
    --work "${work_dir}" \
    --replace

  if [[ "${ephemeral}" == "true" ]]; then
    printf '%s\n' --ephemeral
  fi
}

# deregister removes the runner registration. Best-effort: failures are logged
# but do not abort shutdown.
deregister() {
  local token="$1"
  printf '>>> Removing runner registration\n' >&2
  ./config.sh remove --token "${token}" || \
    printf 'WARN: failed to remove runner registration\n' >&2
}

# shutdown stops the runner process first (config.sh remove fails while the
# runner is still running), then deregisters. Invoked from the signal trap.
shutdown() {
  local token="$1"
  local pid="${2:-}"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    printf '>>> Stopping runner process %s\n' "${pid}" >&2
    kill -TERM "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
  fi
  deregister "${token}"
}

main() {
  local repo_url="${RUNNER_REPO_URL:-}"
  local token="${RUNNER_TOKEN:-}"

  validate_env "${repo_url}" "${token}"

  local name="${RUNNER_NAME:-$(hostname)}"
  local labels
  labels="$(resolve_labels "${RUNNER_LABELS:-}")"
  local work_dir="${RUNNER_WORK_DIR:-_work}"
  local ephemeral="${RUNNER_EPHEMERAL:-false}"

  # Read the generated arguments into an array (one per line).
  local config_args=()
  local line
  while IFS= read -r line; do
    config_args+=("${line}")
  done < <(build_config_args \
    "${repo_url}" "${token}" "${name}" "${labels}" "${work_dir}" "${ephemeral}")

  printf '>>> Configuring runner %s with labels %s\n' "${name}" "${labels}" >&2
  ./config.sh "${config_args[@]}"

  # Install the shutdown trap once configured so we always deregister. The
  # runner process is stopped before removal (config.sh remove fails while
  # the runner is still running).
  trap 'shutdown "${token}" "${run_pid:-}"; exit 130' SIGINT SIGTERM

  printf '>>> Starting runner\n' >&2
  # Run in the background and wait so the trap fires promptly on signals.
  ./run.sh &
  local run_pid=$!
  wait "${run_pid}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
