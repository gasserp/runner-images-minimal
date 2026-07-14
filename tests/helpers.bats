#!/usr/bin/env bats
#
# Unit tests for the shared logging helpers in scripts/helpers.sh.

setup() {
  HELPERS="${BATS_TEST_DIRNAME}/../images/ubuntu/scripts/helpers.sh"
  source "${HELPERS}"
}

@test "log prefixes messages with '>>> ' on stderr" {
  run log "hello there"
  [ "${status}" -eq 0 ]
  [ "${output}" = ">>> hello there" ]
}

@test "log joins multiple arguments with spaces (like printf '%s')" {
  run log "hello" "there" "world"
  [ "${status}" -eq 0 ]
  [ "${output}" = ">>> hello there world" ]
}

@test "info is an alias of log" {
  run info "same as log"
  [ "${status}" -eq 0 ]
  [ "${output}" = ">>> same as log" ]
}

@test "err prefixes messages with 'ERROR: ' on stderr" {
  run err "something broke"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ERROR: something broke" ]
}

@test "err returns success itself (only formats the message)" {
  run err "non-fatal by itself"
  [ "${status}" -eq 0 ]
}
