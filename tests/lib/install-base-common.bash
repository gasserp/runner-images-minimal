#!/usr/bin/env bash
#
# install-base-common.bash - shared setup + assertions for the per-distro
# install-base.bats variants (install-base-ubuntu.bats, install-base-ubi9.bats).
# Loaded via bats' `load` so both distros are held to the same baseline
# checks instead of duplicating them.
#
# main() itself calls apt-get/microdnf and is not exercised here (that's the
# image build's job); instead we assert on the declarative BASE_PACKAGES list
# that drives it, since a missing entry there would silently break the built
# image (e.g. validate-image.sh's binary checks).

# install_base_setup replicates the build-time layout for distro "$1": the
# Dockerfile COPYs common/helpers.sh and the distro's install-base.sh
# alongside each other into /tmp/scripts/, and install-base.sh sources
# helpers.sh from its own directory at runtime. We copy both into
# BATS_TEST_TMPDIR and source the copy from there, so the real sourcing path
# is exercised rather than a test-only shortcut.
install_base_setup() {
  local distro="$1"
  local src_dir="${BATS_TEST_DIRNAME}/../images"
  local dest_dir="${BATS_TEST_TMPDIR}/install-base"

  mkdir -p "${dest_dir}"
  cp "${src_dir}/${distro}/scripts/install-base.sh" "${dest_dir}/"
  cp "${src_dir}/common/helpers.sh" "${dest_dir}/"

  SCRIPT="${dest_dir}/install-base.sh"
  source "${SCRIPT}"
}

# --- shared assertions, called from each distro's @test bodies ---------------

assert_base_packages_nonempty() {
  [ "${#BASE_PACKAGES[@]}" -gt 0 ]
}

# assert_base_packages_includes_runtime_tools checks each package named in
# "$@" — the required set differs per distro (e.g. ubi9-minimal already ships
# curl via curl-minimal, so its list omits curl).
assert_base_packages_includes_runtime_tools() {
  local pkg
  [ "$#" -gt 0 ]
  for pkg in "$@"; do
    assert_base_packages_contains "${pkg}"
  done
}

assert_base_packages_no_duplicates() {
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

# assert_base_packages_contains succeeds iff $1 is present in BASE_PACKAGES.
assert_base_packages_contains() {
  local pkg="$1" candidate
  for candidate in "${BASE_PACKAGES[@]}"; do
    [[ "${candidate}" == "${pkg}" ]] && return 0
  done
  return 1
}
