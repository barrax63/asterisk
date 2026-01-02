# =============================================================================
# Stage 1: Builder - compile and install Asterisk 20 on Debian 12 (bookworm)
# =============================================================================
FROM debian:bookworm-slim AS builder

# Non-interactive apt
ENV DEBIAN_FRONTEND=noninteractive \
    ASTERISK_VERSION=20-current

# Build dependencies and useful tools for the build process
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        wget \
        libxml2-dev \
        libncurses5-dev \
        libsqlite3-dev \
        uuid-dev \
        libjansson-dev \
        libssl-dev \
        libedit-dev \
        ca-certificates \
        curl \
        iproute2 \
        net-tools \
        procps && \
    rm -rf /var/lib/apt/lists/*

# Build Asterisk in /usr/src (as in your guide)
WORKDIR /usr/src

# Download, extract, build, and install Asterisk plus sample configs & init scripts
RUN apt-get update && \
    wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VERSION}.tar.gz && \
    tar xvf asterisk-${ASTERISK_VERSION}.tar.gz && \
    cd asterisk-20.* && \
    # Install additional script dependencies (force apt-get, not aptitude)
    ASTERISK_PREFER_APTITUDE=no contrib/scripts/install_prereq install && \
    # Configure the build
    ./configure && \
    # Compile using all available CPU cores
    make -j"$(nproc)" && \
    # Install the compiled binaries and modules
    make install && \
    # Install sample configuration files
    make samples && \
    # Install startup scripts / system integration
    make config && \
    # Refresh runtime linker cache
    ldconfig && \
    # Clean up build sources to keep builder stage smaller
    cd /usr/src && \
    rm -rf asterisk-20.* asterisk-${ASTERISK_VERSION}.tar.gz


# =============================================================================
# Stage 2: Runtime image - minimal Asterisk runtime on Debian 12 (bookworm)
# =============================================================================
FROM debian:bookworm-slim

# OCI Image Specification Labels
LABEL org.opencontainers.image.title="asterisk-20" \
      org.opencontainers.image.description="Production Asterisk 20 running on Debian 12 (bookworm-slim)" \
      org.opencontainers.image.authors="Noah Nowak <nnowak@cryshell.com>" \
      org.opencontainers.image.url="https://github.com/barrax63/asterisk" \
      org.opencontainers.image.source="https://github.com/barrax63/asterisk" \
      org.opencontainers.image.documentation="https://github.com/barrax63/asterisk/blob/main/README.md" \
      org.opencontainers.image.base.name="docker.io/library/debian:bookworm-slim"

# Non-interactive apt and Asterisk user/group defaults
ENV DEBIAN_FRONTEND=noninteractive \
    ASTERISK_USER=asterisk \
    ASTERISK_GROUP=asterisk

# Runtime dependencies only (toolchain is *not* installed here)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libxml2-dev \
        libncurses5-dev \
        libsqlite3-dev \
        uuid-dev \
        libjansson-dev \
        libssl-dev \
        libedit-dev \
        libxslt1.1 \
        liburiparser1 \
        ca-certificates \
        iproute2 \
        procps && \
    ldconfig && \
    rm -rf /var/lib/apt/lists/*

# Copy Asterisk binaries, modules, configs and runtime skeleton from builder
# - Binary: /usr/sbin/asterisk
# - Modules: /usr/lib/asterisk
# - Config: /etc/asterisk
# - Data: /var/lib/asterisk
# - Spool: /var/spool/asterisk
# - Logs: /var/log/asterisk
COPY --from=builder /usr/sbin/asterisk /usr/sbin/asterisk
COPY --from=builder /usr/lib/asterisk /usr/lib/asterisk
COPY --from=builder /usr/lib/libasterisk*.so* /usr/lib/
COPY --from=builder /etc/asterisk /etc/asterisk
COPY --from=builder /var/lib/asterisk /var/lib/asterisk
COPY --from=builder /var/spool/asterisk /var/spool/asterisk
COPY --from=builder /var/log/asterisk /var/log/asterisk

# Create a dedicated asterisk user/group and fix permissions,
# and configure the history file location.
RUN set -eux; \
    # Create group and user (system user, no shell, home at /var/lib/asterisk)
    groupadd -r "${ASTERISK_GROUP}" && \
    useradd  -r -d /var/lib/asterisk -g "${ASTERISK_GROUP}" "${ASTERISK_USER}" && \
    \
    # Ensure directories exist (COPY above should have created them, but we
    # re-create idempotently in case of future changes)
    mkdir -p /var/lib/asterisk /var/log/asterisk /var/spool/asterisk && \
    \
    # Set ownership for Asterisk directories
    chown -R "${ASTERISK_USER}:${ASTERISK_GROUP}" /etc/asterisk && \
    chown -R "${ASTERISK_USER}:${ASTERISK_GROUP}" /var/lib/asterisk /var/log/asterisk /var/spool/asterisk && \
    chown -R "${ASTERISK_USER}:${ASTERISK_GROUP}" /usr/lib/asterisk && \
    \
    # Enable runuser/rungroup in /etc/asterisk/asterisk.conf
    sed -i 's/;runuser/runuser/g'   /etc/asterisk/asterisk.conf && \
    sed -i 's/;rungroup/rungroup/g' /etc/asterisk/asterisk.conf && \
    \
    # Create directory for Asterisk CLI history
    mkdir -p /var/lib/asterisk/.asterisk && \
    chown "${ASTERISK_USER}:${ASTERISK_GROUP}" /var/lib/asterisk/.asterisk && \
    \
    # Ensure astctlhistory is configured (append only if not already present)
    grep -q 'astctlhistory' /etc/asterisk/asterisk.conf || \
      printf '\n[options]\nastctlhistory => /var/lib/asterisk/.asterisk/.asterisk_history\n' \
      >> /etc/asterisk/asterisk.conf && \
    \
    # Ensure runtime PID/control dir exists and is owned by asterisk
    mkdir -p /var/run/asterisk && \
    chown -R "${ASTERISK_USER}:${ASTERISK_GROUP}" /var/run/asterisk && \
    ldconfig

# Volumes for persistent configuration, data and logs inside the container.
# On the host, docker-compose will bind-mount:
#   ./asterisk/config -> /etc/asterisk
#   ./asterisk/data   -> /var/lib/asterisk
#   ./asterisk/logs   -> /var/log/asterisk
VOLUME ["/etc/asterisk", "/var/lib/asterisk", "/var/log/asterisk", "/var/spool/asterisk"]

# Work inside Asterisk data directory
WORKDIR /var/lib/asterisk

# SIP signalling and RTP ports
EXPOSE 5060/tcp 5060/udp 10000-20000/udp

# Health check using the Asterisk CLI
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD asterisk -rx "core show version" || exit 1

# Run as non-root asterisk user
USER ${ASTERISK_USER}

# Start Asterisk in the foreground
ENTRYPOINT ["asterisk"]
CMD ["-f", "-vvv"]
