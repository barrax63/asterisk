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
    # Build menuselect binary/options
    make menuselect.makeopts && \
    # Disable modules for lean IVR-only build (keeping only PJSIP + alaw/ulaw/g722)
    menuselect/menuselect \
      --disable res_config_pgsql \
      --disable res_config_ldap \
      --disable res_config_odbc \
      --disable res_odbc \
      --disable res_odbc_transaction \
      --disable func_odbc \
      --disable cdr_pgsql \
      --disable cel_pgsql \
      --disable cdr_odbc \
      --disable cel_odbc \
      --disable cdr_tds \
      --disable cel_tds \
      --disable cdr_radius \
      --disable cel_radius \
      --disable res_calendar_icalendar \
      --disable res_calendar_ews \
      --disable res_calendar_caldav \
      --disable res_calendar_exchange \
      --disable app_jack \
      --disable chan_alsa \
      --disable format_ogg_vorbis \
      --disable res_phoneprov \
      --disable chan_sip \
      --disable chan_iax2 \
      --disable chan_mgcp \
      --disable chan_skinny \
      --disable chan_unistim \
      --disable chan_ooh323 \
      --disable chan_dahdi \
      --disable chan_mobile \
      --disable chan_console \
      --disable app_voicemail \
      --disable app_directory \
      --disable app_minivm \
      --disable app_confbridge \
      --disable app_meetme \
      --disable app_queue \
      --disable app_agent_pool \
      --disable app_chanspy \
      --disable res_parking \
      --disable res_fax \
      --disable res_fax_spandsp \
      --disable app_celgenuserevent \
      --disable app_morsecode \
      --disable app_getcpeid \
      --disable app_adsiprog \
      --disable app_alarmreceiver \
      --disable app_amd \
      --disable app_festival \
      --disable app_dictate \
      --disable app_dumpchan \
      --disable app_externalivr \
      --disable app_followme \
      --disable app_forkcdr \
      --disable app_page \
      --disable app_record \
      --disable app_sms \
      --disable app_speech_utils \
      --disable app_test \
      --disable app_zapateller \
      --disable res_ari \
      --disable res_ari_applications \
      --disable res_ari_asterisk \
      --disable res_ari_bridges \
      --disable res_ari_channels \
      --disable res_ari_device_states \
      --disable res_ari_endpoints \
      --disable res_ari_events \
      --disable res_ari_mailboxes \
      --disable res_ari_model \
      --disable res_ari_playbacks \
      --disable res_ari_recordings \
      --disable res_ari_sounds \
      --disable res_http_websocket \
      --disable res_hep \
      --disable res_hep_pjsip \
      --disable res_hep_rtcp \
      --disable res_snmp \
      --disable res_corosync \
      --disable res_xmpp \
      --disable chan_motif \
      --disable res_musiconhold \
      --disable codec_ilbc \
      --disable codec_lpc10 \
      --disable codec_speex \
      --disable codec_opus \
      --disable codec_silk \
      --disable codec_siren7 \
      --disable codec_siren14 \
      --disable codec_g726 \
      --disable codec_adpcm \
      --disable codec_gsm \
      --disable codec_resample \
      --disable codec_dahdi \
      --disable format_g719 \
      --disable format_g723 \
      --disable format_g726 \
      --disable format_g729 \
      --disable format_siren7 \
      --disable format_siren14 \
      --disable format_sln \
      --disable format_vox \
      --disable format_ilbc \
      --disable format_h263 \
      --disable format_h264 \
      menuselect.makeopts && \
    # Compile using all available CPU cores
    make -j"$(nproc)" && \
    # Install the compiled binaries and modules
    make install && \
    # Create minimal config directories (no samples)
    mkdir -p /etc/asterisk && \
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
        libneon27-gnutls \
        libcurl4 \
        libgsm1 \
        libsnmp40 \
        libpq5 \
        libiksemel3 \
        libodbc2 \
        libldap-2.5-0 \
        libsrtp2-1 \
        liblua5.2-0 \
        libgmime-3.0-0 \
        libspandsp2 \
        libspeex1 \
        libspeexdsp1 \
        libcodec2-1.0 \
        libvorbis0a \
        libvorbisenc2 \
        libresample1 \
        libogg0 \
        libportaudio2 \
        libjack-jackd2-0 \
        libsybdb5 \
        libradcli4 \
        libunbound8 \
        libcap2-bin \
        liburiparser1 \
        ca-certificates \
        iproute2 \
        procps \
        gosu && \
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
COPY --from=builder /var/lib/asterisk /var/lib/asterisk
COPY --from=builder /var/spool/asterisk /var/spool/asterisk
COPY --from=builder /var/log/asterisk /var/log/asterisk
# Preserve pristine runtime tree (including XML docs) for bind-mount restores
RUN cp -a /var/lib/asterisk /usr/share/asterisk-runtime && \
    chown -R root:root /usr/share/asterisk-runtime

# Copy configuration files
COPY config/ /etc/asterisk/

# Preserve pristine configuration files for bind-mount restores
RUN cp -a /etc/asterisk /usr/share/asterisk-config && \
    chown -R root:root /usr/share/asterisk-config

# Copy data and sound files
COPY data/ /var/lib/asterisk/

# Copy entrypoint script for environment variable substitution
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Create a dedicated asterisk user/group and fix permissions,
# and configure the history file location.
RUN set -eux; \
    # Create group and user (without fixed UID/GID, home at /var/lib/asterisk)
    # The entrypoint will dynamically adjust UID/GID based on mounted volumes
    groupadd -r "${ASTERISK_GROUP}" && \
    useradd  -r -d /var/lib/asterisk -g "${ASTERISK_GROUP}" "${ASTERISK_USER}" && \
    \
    # Ensure directories exist (COPY above should have created them, but we
    # re-create idempotently in case of future changes)
    mkdir -p /opt/asterisk /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk && \
    \
    # Set ownership for Asterisk directories
    chown -R "${ASTERISK_USER}:${ASTERISK_GROUP}" /etc/asterisk && \
    chown -R "${ASTERISK_USER}:${ASTERISK_GROUP}" /var/lib/asterisk /var/log/asterisk /var/spool/asterisk && \
    chown -R "${ASTERISK_USER}:${ASTERISK_GROUP}" /usr/lib/asterisk && \
    \
    # Prepare call recording path used by the dialplan
    mkdir -p /opt/asterisk/recordings && \
    chown -R "${ASTERISK_USER}:${ASTERISK_GROUP}" /opt/asterisk && \
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
VOLUME ["/opt/asterisk", "/etc/asterisk", "/var/lib/asterisk", "/var/log/asterisk", "/var/spool/asterisk"]

# Work inside Asterisk data directory
WORKDIR /var/lib/asterisk

# SIP signalling and RTP ports
EXPOSE 5060/tcp 5060/udp 10000-20000/udp

# Entrypoint runs as root and drops privileges to asterisk user when launching Asterisk
# This allows the entrypoint to handle bind-mount permissions and documentation restoration
# Use entrypoint script to handle environment variable substitution
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["asterisk", "-f", "-vvv"]
