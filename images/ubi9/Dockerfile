# Minimal containerized self-hosted GitHub Actions runner (RHEL UBI9-minimal).
FROM registry.access.redhat.com/ubi9-minimal:9.5

# RUNNER_VERSION selects the actions/runner release to install.
ARG RUNNER_VERSION=2.317.0
# TARGETARCH is provided automatically by BuildKit; default for classic builds.
ARG TARGETARCH=amd64

# glibc-langpack-en (installed by install-base.sh) provides en_US.UTF-8, so no
# locale-gen step is needed on UBI.
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    RUNNER_HOME=/home/runner \
    RUNNER_USER=runner

# Install base packages in a single cache-friendly layer via the install script.
# Build context is images/, so shared files live under common/ and the
# distro-specific script under ubi9/scripts/. helpers.sh is copied alongside so
# the scripts can source it from their own directory.
COPY common/helpers.sh ubi9/scripts/install-base.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh \
    && /tmp/scripts/install-base.sh

# Create the non-root runner user (uid 1001) with passwordless sudo. This runs
# after install-base.sh because ubi9-minimal has no useradd until shadow-utils
# is installed.
RUN useradd --create-home --home-dir "${RUNNER_HOME}" --uid 1001 \
        --shell /bin/bash "${RUNNER_USER}" \
    && echo "${RUNNER_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner \
    && chmod 0440 /etc/sudoers.d/runner

# Install the GitHub Actions runner. ubi9-minimal has no yum/dnf, so the
# runner's own installdependencies.sh cannot run; its .NET runtime dependencies
# are installed by install-base.sh instead, hence SKIP_INSTALLDEPS=true.
COPY common/install-runner.sh /tmp/scripts/
RUN chmod +x /tmp/scripts/install-runner.sh \
    && SKIP_INSTALLDEPS=true RUNNER_VERSION="${RUNNER_VERSION}" \
       TARGETARCH="${TARGETARCH}" /tmp/scripts/install-runner.sh \
    && rm -rf /tmp/scripts

# Install the entrypoint.
COPY --chown=runner:runner common/entrypoint.sh "${RUNNER_HOME}/entrypoint.sh"
RUN chmod +x "${RUNNER_HOME}/entrypoint.sh"

WORKDIR /home/runner
USER runner

ENTRYPOINT ["/home/runner/entrypoint.sh"]
