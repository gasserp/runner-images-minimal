# Minimal containerized self-hosted GitHub Actions runner (Ubuntu 24.04).
FROM ubuntu:24.04

# RUNNER_VERSION selects the actions/runner release to install.
ARG RUNNER_VERSION=2.317.0
# TARGETARCH is provided automatically by BuildKit; default for classic builds.
ARG TARGETARCH=amd64

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    RUNNER_HOME=/home/runner \
    RUNNER_USER=runner

# Install base packages in a single cache-friendly layer via the install script.
COPY scripts/helpers.sh scripts/install-base.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh \
    && /tmp/scripts/install-base.sh

# Create the non-root runner user (uid 1001) with passwordless sudo.
RUN useradd --create-home --home-dir "${RUNNER_HOME}" --uid 1001 \
        --shell /bin/bash "${RUNNER_USER}" \
    && echo "${RUNNER_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner \
    && chmod 0440 /etc/sudoers.d/runner

# Install the GitHub Actions runner and its dependencies.
COPY scripts/install-runner.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/install-runner.sh \
    && RUNNER_VERSION="${RUNNER_VERSION}" TARGETARCH="${TARGETARCH}" \
       /tmp/scripts/install-runner.sh \
    && rm -rf /tmp/scripts

# Install the entrypoint.
COPY --chown=runner:runner entrypoint.sh "${RUNNER_HOME}/entrypoint.sh"
RUN chmod +x "${RUNNER_HOME}/entrypoint.sh"

WORKDIR /home/runner
USER runner

ENTRYPOINT ["/home/runner/entrypoint.sh"]
