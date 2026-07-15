# Rust flavor: bakes a pinned Rust toolchain (rustc + cargo) into a runner base image.
#
# Layered on an apt-based runner-images-minimal base (ubuntu only) via the
# BASE_IMAGE build arg. Intended for ephemeral runner fleets that run Rust:
# the tool is baked in at build time (checksum-verified) so jobs never download
# it, and RUNNER_DISABLE_UPDATE is defaulted on to skip the runner self-update.
ARG BASE_IMAGE=runner-images-minimal:ubuntu
FROM ${BASE_IMAGE}

# RUST_VERSION selects the Rust toolchain release to install.
ARG RUST_VERSION=1.83.0
# TARGETARCH is provided automatically by BuildKit; default for classic builds.
ARG TARGETARCH=amd64

# Install Rust as root. Build context is images/, so helpers.sh lives under
# common/ and the install script under flavors/rust/scripts/; helpers.sh is
# copied alongside so the script can source it from its own directory.
USER root
COPY common/helpers.sh flavors/rust/scripts/install-rust.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh \
    && RUST_VERSION="${RUST_VERSION}" TARGETARCH="${TARGETARCH}" \
       /tmp/scripts/install-rust.sh \
    && rm -rf /tmp/scripts

# Advertise a rust label so workflows can target `runs-on: [self-hosted,
# rust]` without any deploy-time RUNNER_LABELS config, and disable the
# runner self-update by default (flavors target ephemeral fleets). Both are
# plain ENV defaults and can be overridden at `docker run` time.
ENV RUNNER_LABELS=self-hosted,linux,minimal,rust \
    RUNNER_DISABLE_UPDATE=true

# Drop back to the non-root runner user (the base image's ENTRYPOINT is inherited).
USER runner