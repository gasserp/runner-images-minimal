# .NET flavor: installs the .NET SDK from the distro archive.
#
# Layered on an apt-based runner-images-minimal base (ubuntu only) via the
# BASE_IMAGE build arg. Intended for ephemeral runner fleets that run .NET jobs:
# the tool is baked in at build time so jobs never download it, and RUNNER_DISABLE_UPDATE
# is defaulted on to skip the runner self-update.
ARG BASE_IMAGE=runner-images-minimal:ubuntu
FROM ${BASE_IMAGE}

# Install .NET as root. Build context is images/, so helpers.sh lives under
# common/ and the install script under flavors/dotnet/scripts/; helpers.sh is
# copied alongside so the script can source it from its own directory.
USER root
COPY common/helpers.sh flavors/dotnet/scripts/install-dotnet.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh \
    && /tmp/scripts/install-dotnet.sh \
    && rm -rf /tmp/scripts

# Advertise a dotnet label so workflows can target `runs-on: [self-hosted,
# dotnet]` without any deploy-time RUNNER_LABELS config, and disable the
# runner self-update by default (flavors target ephemeral fleets). Both are
# plain ENV defaults and can be overridden at `docker run` time.
ENV RUNNER_LABELS=self-hosted,linux,minimal,dotnet \
    RUNNER_DISABLE_UPDATE=true \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1

# Drop back to the non-root runner user (the base image's ENTRYPOINT is inherited).
USER runner