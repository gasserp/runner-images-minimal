#!/usr/bin/env bash
#
# helpers.sh - shared logging helpers sourced by the install scripts.
#
# This file is meant to be sourced, not executed directly. It intentionally
# does not set shell options so that the sourcing script keeps full control
# over `set -euo pipefail`.

# Emit a plain log line to stderr with a leading marker.
log() {
  printf '>>> %s\n' "$*" >&2
}

# Informational message (alias of log, kept for readable call sites).
info() {
  log "$@"
}

# Error message to stderr with an ERROR prefix.
err() {
  printf 'ERROR: %s\n' "$*" >&2
}
