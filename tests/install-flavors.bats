#!/usr/bin/env bats
#
# Unit tests for all flavor install scripts: shared functionality like arch
# mapping and guard clauses across download-based flavors, and package lists
# for apt-based flavors.
#
# This file covers the shared surface of all flavor install scripts. For
# per-script deep-dive patterns (like end-to-end testing), see
# tests/install-terraform.bats and its pattern.

# setup replicates the build-time layout: the Dockerfile COPYs
# common/helpers.sh and flavors/<flavor>/scripts/install-<flavor>.sh
# alongside each other into /tmp/scripts/, and install-<flavor>.sh sources
# helpers.sh from its own directory (SCRIPT_DIR) at runtime. We copy both
# into BATS_TEST_TMPDIR and source the copy from there, so the real sourcing
# path is exercised rather than a test-only shortcut.
setup() {
  local src_dir="${BATS_TEST_DIRNAME}/../images"
  local dest_dir="${BATS_TEST_TMPDIR}/install-node"

  mkdir -p "${dest_dir}"
  cp "${src_dir}/flavors/node/scripts/install-node.sh" "${dest_dir}/"
  cp "${src_dir}/common/helpers.sh" "${dest_dir}/"

  SCRIPT="${dest_dir}/install-node.sh"
  # Sourcing is safe: the main guard prevents execution.
  source "${SCRIPT}"
}

# --- map_arch -----------------------------------------------------------------

@test "map_arch maps Docker arches for node flavor" {
  run bash -c "source '${BATS_TEST_TMPDIR}/install-node/install-node.sh'; map_arch 'amd64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "x64" ]

  run bash -c "source '${BATS_TEST_TMPDIR}/install-node/install-node.sh'; map_arch 'x64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "x64" ]

  run bash -c "source '${BATS_TEST_TMPDIR}/install-node/install-node.sh'; map_arch 'x86_64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "x64" ]

  run bash -c "source '${BATS_TEST_TMPDIR}/install-node/install-node.sh'; map_arch 'arm64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "arm64" ]

  run bash -c "source '${BATS_TEST_TMPDIR}/install-node/install-node.sh'; map_arch 'aarch64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "arm64" ]
}

@test "map_arch maps Docker arches for go flavor" {
  local src_dir="${BATS_TEST_DIRNAME}/../images"
  local dest_dir="${BATS_TEST_TMPDIR}/install-go"

  mkdir -p "${dest_dir}"
  cp "${src_dir}/flavors/go/scripts/install-go.sh" "${dest_dir}/"
  cp "${src_dir}/common/helpers.sh" "${dest_dir}/"

  run bash -c "source '${dest_dir}/install-go.sh'; map_arch 'amd64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "amd64" ]

  run bash -c "source '${dest_dir}/install-go.sh'; map_arch 'x64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "amd64" ]

  run bash -c "source '${dest_dir}/install-go.sh'; map_arch 'x86_64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "amd64" ]

  run bash -c "source '${dest_dir}/install-go.sh'; map_arch 'arm64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "arm64" ]

  run bash -c "source '${dest_dir}/install-go.sh'; map_arch 'aarch64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "arm64" ]
}

@test "map_arch maps Docker arches for dart flavor" {
  local src_dir="${BATS_TEST_DIRNAME}/../images"
  local dest_dir="${BATS_TEST_TMPDIR}/install-dart"

  mkdir -p "${dest_dir}"
  cp "${src_dir}/flavors/dart/scripts/install-dart.sh" "${dest_dir}/"
  cp "${src_dir}/common/helpers.sh" "${dest_dir}/"

  run bash -c "source '${dest_dir}/install-dart.sh'; map_arch 'amd64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "x64" ]

  run bash -c "source '${dest_dir}/install-dart.sh'; map_arch 'x64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "x64" ]

  run bash -c "source '${dest_dir}/install-dart.sh'; map_arch 'x86_64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "x64" ]

  run bash -c "source '${dest_dir}/install-dart.sh'; map_arch 'arm64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "arm64" ]

  run bash -c "source '${dest_dir}/install-dart.sh'; map_arch 'aarch64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "arm64" ]
}

@test "map_arch maps Docker arches for rust flavor" {
  local src_dir="${BATS_TEST_DIRNAME}/../images"
  local dest_dir="${BATS_TEST_TMPDIR}/install-rust"

  mkdir -p "${dest_dir}"
  cp "${src_dir}/flavors/rust/scripts/install-rust.sh" "${dest_dir}/"
  cp "${src_dir}/common/helpers.sh" "${dest_dir}/"

  run bash -c "source '${dest_dir}/install-rust.sh'; map_arch 'amd64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "x86_64-unknown-linux-gnu" ]

  run bash -c "source '${dest_dir}/install-rust.sh'; map_arch 'x64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "x86_64-unknown-linux-gnu" ]

  run bash -c "source '${dest_dir}/install-rust.sh'; map_arch 'x86_64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "x86_64-unknown-linux-gnu" ]

  run bash -c "source '${dest_dir}/install-rust.sh'; map_arch 'arm64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "aarch64-unknown-linux-gnu" ]

  run bash -c "source '${dest_dir}/install-rust.sh'; map_arch 'aarch64'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "aarch64-unknown-linux-gnu" ]
}

@test "map_arch rejects unsupported arches for download-based flavors" {
  local download_flavors=("node" "go" "dart" "rust")

  for flavor in "${download_flavors[@]}"; do
    local src_dir="${BATS_TEST_DIRNAME}/../images"
    local dest_dir="${BATS_TEST_TMPDIR}/install-${flavor}"

    mkdir -p "${dest_dir}"
    cp "${src_dir}/flavors/${flavor}/scripts/install-${flavor}.sh" "${dest_dir}/"
    cp "${src_dir}/common/helpers.sh" "${dest_dir}/"

    run bash -c "source '${dest_dir}/install-${flavor}.sh'; map_arch 'riscv64'"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Unsupported architecture"* ]]
    [[ "${output}" == *"riscv64"* ]]
  done
}

# --- main() guard clauses (fail before touching the network) ------------------

setup_stub_marker_bin() {
  local fakebin="$1"
  local marker_dir="$2"
  mkdir -p "${fakebin}" "${marker_dir}"

  local cmd
  for cmd in curl apt-get; do
    cat >"${fakebin}/${cmd}" <<EOF
#!/usr/bin/env bash
printf 'called\n' >> "${marker_dir}/${cmd}.called"
echo "STUB: ${cmd} should not run past a guard clause" >&2
exit 1
EOF
    chmod +x "${fakebin}/${cmd}"
  done
}

@test "main fails fast when NODE_VERSION is unset (node flavor)" {
  local src_dir="${BATS_TEST_DIRNAME}/../images"
  local dest_dir="${BATS_TEST_TMPDIR}/install-node"

  mkdir -p "${dest_dir}"
  cp "${src_dir}/flavors/node/scripts/install-node.sh" "${dest_dir}/"
  cp "${src_dir}/common/helpers.sh" "${dest_dir}/"

  local fakebin="${BATS_TEST_TMPDIR}/fakebin-guard-node-unset"
  local marker_dir="${BATS_TEST_TMPDIR}/markers-guard-node-unset"
  setup_stub_marker_bin "${fakebin}" "${marker_dir}"

  run bash -c "
    export PATH='${fakebin}:'\"\${PATH}\"
    unset NODE_VERSION
    source '${dest_dir}/install-node.sh'
    main
  "

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"NODE_VERSION is required"* ]]
  [ ! -f "${marker_dir}/curl.called" ]
}

@test "main fails fast when GO_VERSION is unset (go flavor)" {
  local src_dir="${BATS_TEST_DIRNAME}/../images"
  local dest_dir="${BATS_TEST_TMPDIR}/install-go"

  mkdir -p "${dest_dir}"
  cp "${src_dir}/flavors/go/scripts/install-go.sh" "${dest_dir}/"
  cp "${src_dir}/common/helpers.sh" "${dest_dir}/"

  local fakebin="${BATS_TEST_TMPDIR}/fakebin-guard-go-unset"
  local marker_dir="${BATS_TEST_TMPDIR}/markers-guard-go-unset"
  setup_stub_marker_bin "${fakebin}" "${marker_dir}"

  run bash -c "
    export PATH='${fakebin}:'\"\${PATH}\"
    unset GO_VERSION
    source '${dest_dir}/install-go.sh'
    main
  "

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"GO_VERSION is required"* ]]
  [ ! -f "${marker_dir}/curl.called" ]
}

@test "main fails fast when DART_VERSION is unset (dart flavor)" {
  local src_dir="${BATS_TEST_DIRNAME}/../images"
  local dest_dir="${BATS_TEST_TMPDIR}/install-dart"

  mkdir -p "${dest_dir}"
  cp "${src_dir}/flavors/dart/scripts/install-dart.sh" "${dest_dir}/"
  cp "${src_dir}/common/helpers.sh" "${dest_dir}/"

  local fakebin="${BATS_TEST_TMPDIR}/fakebin-guard-dart-unset"
  local marker_dir="${BATS_TEST_TMPDIR}/markers-guard-dart-unset"
  setup_stub_marker_bin "${fakebin}" "${marker_dir}"

  run bash -c "
    export PATH='${fakebin}:'\"\${PATH}\"
    unset DART_VERSION
    source '${dest_dir}/install-dart.sh'
    main
  "

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"DART_VERSION is required"* ]]
  [ ! -f "${marker_dir}/curl.called" ]
}

@test "main fails fast when RUST_VERSION is unset (rust flavor)" {
  local src_dir="${BATS_TEST_DIRNAME}/../images"
  local dest_dir="${BATS_TEST_TMPDIR}/install-rust"

  mkdir -p "${dest_dir}"
  cp "${src_dir}/flavors/rust/scripts/install-rust.sh" "${dest_dir}/"
  cp "${src_dir}/common/helpers.sh" "${dest_dir}/"

  local fakebin="${BATS_TEST_TMPDIR}/fakebin-guard-rust-unset"
  local marker_dir="${BATS_TEST_TMPDIR}/markers-guard-rust-unset"
  setup_stub_marker_bin "${fakebin}" "${marker_dir}"

  run bash -c "
    export PATH='${fakebin}:'\"\${PATH}\"
    unset RUST_VERSION
    source '${dest_dir}/install-rust.sh'
    main
  "

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"RUST_VERSION is required"* ]]
  [ ! -f "${marker_dir}/curl.called" ]
}

# --- apt-based flavor scripts declare their expected packages -----------------

@test "apt-based flavor scripts declare their expected packages" {
  local apt_flavors=("python" "java" "ruby" "dotnet" "php")

  for flavor in "${apt_flavors[@]}"; do
    local src_dir="${BATS_TEST_DIRNAME}/../images"
    local dest_dir="${BATS_TEST_TMPDIR}/install-${flavor}"

    mkdir -p "${dest_dir}"
    cp "${src_dir}/flavors/${flavor}/scripts/install-${flavor}.sh" "${dest_dir}/"
    cp "${src_dir}/common/helpers.sh" "${dest_dir}/"

    run bash -c "source '${dest_dir}/install-${flavor}.sh'; printf '%s\n' \"\${PACKAGES[@]}\""

    case "${flavor}" in
      python)
        # Check that all required packages are present
        [[ "${output}" == *"python3"* ]]
        [[ "${output}" == *"python3-pip"* ]]
        [[ "${output}" == *"python3-venv"* ]]
        ;;
      java)
        [[ "${output}" == *"openjdk-21-jdk-headless"* ]]
        [[ "${output}" == *"maven"* ]]
        ;;
      ruby)
        [[ "${output}" == *"ruby-full"* ]]
        [[ "${output}" == *"build-essential"* ]]
        ;;
      dotnet)
        [[ "${output}" == *"dotnet-sdk-8.0"* ]]
        ;;
      php)
        [[ "${output}" == *"php-cli"* ]]
        [[ "${output}" == *"php-curl"* ]]
        [[ "${output}" == *"php-mbstring"* ]]
        [[ "${output}" == *"php-xml"* ]]
        [[ "${output}" == *"php-zip"* ]]
        ;;
    esac
  done
}

@test "php main fails fast when COMPOSER_VERSION is unset" {
  local src_dir="${BATS_TEST_DIRNAME}/../images"
  local dest_dir="${BATS_TEST_TMPDIR}/install-php"

  mkdir -p "${dest_dir}"
  cp "${src_dir}/flavors/php/scripts/install-php.sh" "${dest_dir}/"
  cp "${src_dir}/common/helpers.sh" "${dest_dir}/"

  local fakebin="${BATS_TEST_TMPDIR}/fakebin-guard-php-unset"
  local marker_dir="${BATS_TEST_TMPDIR}/markers-guard-php-unset"
  setup_stub_marker_bin "${fakebin}" "${marker_dir}"

  run bash -c "
    export PATH='${fakebin}:'\"\${PATH}\"
    unset COMPOSER_VERSION
    source '${dest_dir}/install-php.sh'
    main
  "

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"COMPOSER_VERSION is required"* ]]
  [ ! -f "${marker_dir}/apt-get.called" ]
}