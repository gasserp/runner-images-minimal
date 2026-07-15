# PHP flavor: installs PHP CLI from the distro archive plus a pinned, checksum-verified Composer.
#
# Layered on an apt-based runner-images-minimal base (ubuntu only) via the
# BASE_IMAGE build arg. Intended for ephemeral runner fleets that run PHP jobs:
# the tool is baked in at build time so jobs never download it, and RUNNER_DISABLE_UPDATE
# is defaulted on to skip the runner self-update.
ARG BASE_IMAGE=runner-images-minimal:ubuntu
FROM ${BASE_IMAGE}

# COMPOSER_VERSION selects the Composer release to install.
ARG COMPOSER_VERSION=2.8.3

# Install PHP as root. Build context is images/, so helpers.sh lives under
# common/ and the install script under flavors/php/scripts/; helpers.sh is
# copied alongside so the script can source it from its own directory.
USER root
COPY common/helpers.sh flavors/php/scripts/install-php.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh \
    && COMPOSER_VERSION="${COMPOSER_VERSION}" \
       /tmp/scripts/install-php.sh \
    && rm -rf /tmp/scripts

# Advertise a php label so workflows can target `runs-on: [self-hosted,
# php]` without any deploy-time RUNNER_LABELS config, and disable the
# runner self-update by default (flavors target ephemeral fleets). Both are
# plain ENV defaults and can be overridden at `docker run` time.
ENV RUNNER_LABELS=self-hosted,linux,minimal,php \
    RUNNER_DISABLE_UPDATE=true

# Drop back to the non-root runner user (the base image's ENTRYPOINT is inherited).
USER runner