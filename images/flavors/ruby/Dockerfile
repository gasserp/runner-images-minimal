# Ruby flavor: installs Ruby (with RubyGems and bundler) plus build tools for native gems.
#
# Layered on an apt-based runner-images-minimal base (ubuntu only) via the
# BASE_IMAGE build arg. Intended for ephemeral runner fleets that run Ruby jobs:
# the tool is baked in at build time so jobs never download it, and RUNNER_DISABLE_UPDATE
# is defaulted on to skip the runner self-update.
ARG BASE_IMAGE=runner-images-minimal:ubuntu
FROM ${BASE_IMAGE}

# Install Ruby as root. Build context is images/, so helpers.sh lives under
# common/ and the install script under flavors/ruby/scripts/; helpers.sh is
# copied alongside so the script can source it from its own directory.
USER root
COPY common/helpers.sh flavors/ruby/scripts/install-ruby.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh \
    && /tmp/scripts/install-ruby.sh \
    && rm -rf /tmp/scripts

# Advertise a ruby label so workflows can target `runs-on: [self-hosted,
# ruby]` without any deploy-time RUNNER_LABELS config, and disable the
# runner self-update by default (flavors target ephemeral fleets). Both are
# plain ENV defaults and can be overridden at `docker run` time.
ENV RUNNER_LABELS=self-hosted,linux,minimal,ruby \
    RUNNER_DISABLE_UPDATE=true

# Drop back to the non-root runner user (the base image's ENTRYPOINT is inherited).
USER runner