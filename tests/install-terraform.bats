#!/usr/bin/env bats
#
# Unit tests for install-terraform.sh: arch mapping and the main() guard
# clauses/end-to-end install flow, mirroring tests/install-runner.bats.

# setup replicates the build-time layout: the Dockerfile COPYs
# common/helpers.sh and flavors/terraform/scripts/install-terraform.sh
# alongside each other into /tmp/scripts/, and install-terraform.sh sources
# helpers.sh from its own directory (SCRIPT_DIR) at runtime. We copy both
# into BATS_TEST_TMPDIR and source the copy from there, so the real sourcing
# path is exercised rather than a test-only shortcut (same approach as
# tests/lib/install-base-common.bash's install_base_setup).
setup() {
  local src_dir="${BATS_TEST_DIRNAME}/../images"
  local dest_dir="${BATS_TEST_TMPDIR}/install-terraform"

  mkdir -p "${dest_dir}"
  cp "${src_dir}/flavors/terraform/scripts/install-terraform.sh" "${dest_dir}/"
  cp "${src_dir}/common/helpers.sh" "${dest_dir}/"

  SCRIPT="${dest_dir}/install-terraform.sh"
  # Sourcing is safe: the main guard prevents execution.
  source "${SCRIPT}"
}

# --- map_arch -----------------------------------------------------------------

@test "map_arch maps amd64 to amd64" {
  run map_arch "amd64"
  [ "${status}" -eq 0 ]
  [ "${output}" = "amd64" ]
}

@test "map_arch maps x64 to amd64" {
  run map_arch "x64"
  [ "${status}" -eq 0 ]
  [ "${output}" = "amd64" ]
}

@test "map_arch maps x86_64 to amd64" {
  run map_arch "x86_64"
  [ "${status}" -eq 0 ]
  [ "${output}" = "amd64" ]
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
# `arch="$(map_arch ...)"` assignment would silently continue into curl
# with an empty arch instead of stopping main() immediately.
#
# curl/unzip/sha256sum are stubbed on PATH as a belt-and-suspenders check:
# each stub records that it was invoked, so we can assert the guard genuinely
# stopped main() before any network tool ran, not merely that the error
# message happened to be printed.

# setup_stub_marker_bin populates $1 with stub curl/unzip/sha256sum
# executables that record their invocation into $2/<cmd>.called and then
# fail loudly, so a guard-clause test that (incorrectly) reached the network
# step fails clearly instead of hanging or reaching out to the internet.
setup_stub_marker_bin() {
  local fakebin="$1"
  local marker_dir="$2"
  mkdir -p "${fakebin}" "${marker_dir}"

  local cmd
  for cmd in curl unzip sha256sum; do
    cat >"${fakebin}/${cmd}" <<EOF
#!/usr/bin/env bash
printf 'called\n' >> "${marker_dir}/${cmd}.called"
echo "STUB: ${cmd} should not run past a guard clause" >&2
exit 1
EOF
    chmod +x "${fakebin}/${cmd}"
  done
}

@test "main fails with a clear message when TERRAFORM_VERSION is unset" {
  local fakebin="${BATS_TEST_TMPDIR}/fakebin-guard-unset"
  local marker_dir="${BATS_TEST_TMPDIR}/markers-guard-unset"
  setup_stub_marker_bin "${fakebin}" "${marker_dir}"

  run bash -c "
    export PATH='${fakebin}:'\"\${PATH}\"
    unset TERRAFORM_VERSION
    source '${SCRIPT}'
    main
  "

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"TERRAFORM_VERSION is required"* ]]
  [ ! -f "${marker_dir}/curl.called" ]
}

@test "main fails with a clear message when TERRAFORM_VERSION is empty" {
  local fakebin="${BATS_TEST_TMPDIR}/fakebin-guard-empty"
  local marker_dir="${BATS_TEST_TMPDIR}/markers-guard-empty"
  setup_stub_marker_bin "${fakebin}" "${marker_dir}"

  TERRAFORM_VERSION="" run bash -c "
    export PATH='${fakebin}:'\"\${PATH}\"
    source '${SCRIPT}'
    main
  "

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"TERRAFORM_VERSION is required"* ]]
  [ ! -f "${marker_dir}/curl.called" ]
}

@test "main fails with a clear message for an unsupported TARGETARCH" {
  local fakebin="${BATS_TEST_TMPDIR}/fakebin-guard-arch"
  local marker_dir="${BATS_TEST_TMPDIR}/markers-guard-arch"
  setup_stub_marker_bin "${fakebin}" "${marker_dir}"

  TERRAFORM_VERSION="1.9.8" TARGETARCH="riscv64" run bash -c "
    export PATH='${fakebin}:'\"\${PATH}\"
    source '${SCRIPT}'
    main
  "

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Unsupported architecture: riscv64"* ]]
  [ ! -f "${marker_dir}/curl.called" ]
}

@test "main defaults TARGETARCH to amd64 when unset (arch guard passes)" {
  # main() reaches the network/filesystem steps once past the arch guard, so
  # we don't run it for real here (no network in the test sandbox). Instead
  # we assert the same default resolution main() uses would map cleanly.
  unset TARGETARCH
  local default_arch="${TARGETARCH:-amd64}"
  run map_arch "${default_arch}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "amd64" ]
}

# --- main() end-to-end against a faked download/install tree ------------------
#
# These exercise main() past the arch guard by stubbing out curl/unzip/
# sha256sum on PATH (no real network access), so we can assert on the
# install flow: the checksum line is grepped/verified, the "binary" lands in
# INSTALL_DIR, and the final smoke check (`terraform version`) succeeds
# against the stubbed executable. Run via a real `bash -c` subprocess (not
# bats' `run` alone) so the script's own `set -euo pipefail` genuinely
# governs main(), same rationale as the guard-clause tests above.

# setup_fake_terraform_install_env populates $1 with stub curl/unzip/
# sha256sum executables. curl writes a placeholder zip and, for the
# SHA256SUMS request, a checksum line naming the expected zip so the
# script's own `grep ... | sha256sum -c -` pipeline has a line to find;
# sha256sum stub then reports success unconditionally (verifying the real
# hash algorithm isn't what this test is about). unzip stub writes a fake,
# executable `terraform` binary into the -d target directory instead of
# extracting a real archive.
setup_fake_terraform_install_env() {
  local fakebin="$1"
  local terraform_version="$2"
  local arch="$3"
  mkdir -p "${fakebin}"

  cat >"${fakebin}/curl" <<EOF
#!/usr/bin/env bash
# Stub curl: writes a placeholder at the -o target. For a SHA256SUMS
# request, the placeholder is a checksum line naming the expected zip so
# the real grep/sha256sum pipeline downstream has something to match.
out=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
case "\${out}" in
  *SHA256SUMS)
    printf 'deadbeefcafebabe0000000000000000000000000000000000000000000000  terraform_${terraform_version}_linux_${arch}.zip\n' >"\${out}"
    ;;
  *)
    : >"\${out}"
    ;;
esac
EOF

  cat >"${fakebin}/sha256sum" <<'EOF'
#!/usr/bin/env bash
# Stub sha256sum: consume stdin (the grep-selected checksum line) and
# report success unconditionally. This test is about the install flow, not
# real cryptographic verification.
cat >/dev/null
exit 0
EOF

  cat >"${fakebin}/unzip" <<'EOF'
#!/usr/bin/env bash
# Stub unzip: writes a fake, executable terraform binary into the -d
# target directory instead of extracting a real archive.
outdir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) outdir="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "${outdir}"
cat >"${outdir}/terraform" <<'BIN'
#!/usr/bin/env bash
printf 'Terraform v0.0.0-fake\n'
BIN
chmod +x "${outdir}/terraform"
EOF

  chmod +x "${fakebin}/curl" "${fakebin}/sha256sum" "${fakebin}/unzip"
}

@test "main downloads, verifies and installs terraform end-to-end (amd64, stubbed network)" {
  local fakebin="${BATS_TEST_TMPDIR}/fakebin-e2e-amd64"
  local install_dir="${BATS_TEST_TMPDIR}/install-dir-e2e-amd64"
  setup_fake_terraform_install_env "${fakebin}" "1.9.8" "amd64"
  mkdir -p "${install_dir}"

  run bash -c "
    export PATH='${fakebin}:${install_dir}:'\"\${PATH}\"
    export TERRAFORM_VERSION='1.9.8'
    export TARGETARCH='amd64'
    export INSTALL_DIR='${install_dir}'
    source '${SCRIPT}'
    main
  "

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Terraform install complete"* ]]
  [[ "${output}" == *"Terraform v0.0.0-fake"* ]]
  [ -x "${install_dir}/terraform" ]
}

@test "main downloads, verifies and installs terraform end-to-end (arm64, stubbed network)" {
  local fakebin="${BATS_TEST_TMPDIR}/fakebin-e2e-arm64"
  local install_dir="${BATS_TEST_TMPDIR}/install-dir-e2e-arm64"
  setup_fake_terraform_install_env "${fakebin}" "1.9.8" "arm64"
  mkdir -p "${install_dir}"

  run bash -c "
    export PATH='${fakebin}:${install_dir}:'\"\${PATH}\"
    export TERRAFORM_VERSION='1.9.8'
    export TARGETARCH='aarch64'
    export INSTALL_DIR='${install_dir}'
    source '${SCRIPT}'
    main
  "

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Terraform install complete"* ]]
  [ -x "${install_dir}/terraform" ]
}

@test "main fails the checksum step when the SHA256SUMS file has no matching line" {
  local fakebin="${BATS_TEST_TMPDIR}/fakebin-e2e-mismatch"
  local install_dir="${BATS_TEST_TMPDIR}/install-dir-e2e-mismatch"
  # Build the stub env for arm64 but tell main() to install amd64, so the
  # SHA256SUMS file curl "downloads" never names the amd64 zip and the
  # `grep ... | sha256sum -c -` pipeline has nothing to match.
  setup_fake_terraform_install_env "${fakebin}" "1.9.8" "arm64"
  mkdir -p "${install_dir}"

  run bash -c "
    export PATH='${fakebin}:${install_dir}:'\"\${PATH}\"
    export TERRAFORM_VERSION='1.9.8'
    export TARGETARCH='amd64'
    export INSTALL_DIR='${install_dir}'
    source '${SCRIPT}'
    main
  "

  [ "${status}" -ne 0 ]
  [ ! -f "${install_dir}/terraform" ]
}
