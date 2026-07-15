# Dart flavor: bakes a pinned Dart SDK into a runner base image.
#
# Layered on top of any runner-images-minimal base (ubuntu or ubi9) via the
# BASE_IMAGE build arg. Intended for ephemeral runner fleets that run Dart:
# the tool is baked in at build time (checksum-verified) so jobs never download
# it, and RUNNER_DISABLE_UPDATE is defaulted on to skip the runner self-update.
ARG BASE_IMAGE=runner-images-minimal:ubuntu
FROM ${BASE_IMAGE}

# DART_VERSION selects the Dart SDK release to install.
ARG DART_VERSION=3.6.0
# TARGETARCH is provided automatically by BuildKit; default for classic builds.
ARG TARGETARCH=amd64

# Install Dart as root. Build context is images/, so helpers.sh lives under
# common/ and the install script under flavors/dart/scripts/; helpers.sh is
# copied alongside so the script can source it from its own directory.
USER root
COPY common/helpers.sh flavors/dart/scripts/install-dart.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh \
    && DART_VERSION="${DART_VERSION}" TARGETARCH="${TARGETARCH}" \
       /tmp/scripts/install-dart.sh \
    && rm -rf /tmp/scripts

# Advertise a dart label so workflows can target `runs-on: [self-hosted,
# dart]` without any deploy-time RUNNER_LABELS config, and disable the
# runner self-update by default (flavors target ephemeral fleets). Both are
# plain ENV defaults and can be overridden at `docker run` time.
ENV RUNNER_LABELS=self-hosted,linux,minimal,dart \
    RUNNER_DISABLE_UPDATE=true

# Drop back to the non-root runner user (the base image's ENTRYPOINT is inherited).
USER runner