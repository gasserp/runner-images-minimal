# Go flavor: bakes a pinned Go toolchain into a runner base image.
#
# Layered on top of any runner-images-minimal base (ubuntu or ubi9) via the
# BASE_IMAGE build arg. Intended for ephemeral runner fleets that run Go:
# the tool is baked in at build time (checksum-verified) so jobs never download
# it, and RUNNER_DISABLE_UPDATE is defaulted on to skip the runner self-update.
ARG BASE_IMAGE=runner-images-minimal:ubuntu
FROM ${BASE_IMAGE}

# GO_VERSION selects the Go release to install.
ARG GO_VERSION=1.23.4
# TARGETARCH is provided automatically by BuildKit; default for classic builds.
ARG TARGETARCH=amd64

# Install Go as root. Build context is images/, so helpers.sh lives under
# common/ and the install script under flavors/go/scripts/; helpers.sh is
# copied alongside so the script can source it from its own directory.
USER root
COPY common/helpers.sh flavors/go/scripts/install-go.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh \
    && GO_VERSION="${GO_VERSION}" TARGETARCH="${TARGETARCH}" \
       /tmp/scripts/install-go.sh \
    && rm -rf /tmp/scripts

# Advertise a go label so workflows can target `runs-on: [self-hosted,
# go]` without any deploy-time RUNNER_LABELS config, and disable the
# runner self-update by default (flavors target ephemeral fleets). Both are
# plain ENV defaults and can be overridden at `docker run` time.
ENV RUNNER_LABELS=self-hosted,linux,minimal,go \
    RUNNER_DISABLE_UPDATE=true

# Drop back to the non-root runner user (the base image's ENTRYPOINT is inherited).
USER runner