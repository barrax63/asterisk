#!/bin/bash
set -e

# This script runs as the asterisk user, so we need to handle file modifications
# The config files are already owned by asterisk user from Dockerfile

CONFIG_DIR="/etc/asterisk"
RUNTIME_CONFIG_DIR="/tmp/asterisk-config"
ACTIVE_CONFIG_DIR="${CONFIG_DIR}"
CONFIG_WRITABLE=true
PJSIP_ORIGINAL="${CONFIG_DIR}/pjsip.conf"
PJSIP_WRITABLE=true
ASTERISK_USER_NAME="${ASTERISK_USER:-asterisk}"
ASTERISK_GROUP_NAME="${ASTERISK_GROUP:-asterisk}"
ASTERISK_ACCOUNT_PRESENT=false
DOC_STASH_DIR="/usr/share/asterisk-runtime/documentation"
DOC_TARGET_DIR="/var/lib/asterisk/documentation"

escape_for_sed() {
    printf '%s' "$1" | sed 's/[\\/&]/\\&/g'
}

if [ -n "${CHOWN_PATHS:-}" ]; then
    CHOWN_TARGETS=()
    while IFS= read -r path; do
        [ -n "${path}" ] && CHOWN_TARGETS+=("${path}")
    done < <(printf '%s\n' "${CHOWN_PATHS}" | tr ':' '\n')
else
    CHOWN_TARGETS=(/etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk /opt/asterisk)
fi

if ! printf '%s' "${ASTERISK_USER_NAME}" | grep -Eq '^[a-z_][a-z0-9_-]{0,31}$'; then
    echo "Invalid ASTERISK_USER '${ASTERISK_USER_NAME}', defaulting to 'asterisk'"
    ASTERISK_USER_NAME="asterisk"
fi

if ! printf '%s' "${ASTERISK_GROUP_NAME}" | grep -Eq '^[a-z_][a-z0-9_-]{0,31}$'; then
    echo "Invalid ASTERISK_GROUP '${ASTERISK_GROUP_NAME}', defaulting to 'asterisk'"
    ASTERISK_GROUP_NAME="asterisk"
fi

if [ ! -d "${CONFIG_DIR}" ]; then
    echo "Config directory ${CONFIG_DIR} not found."
    exit 1
fi

if getent passwd "${ASTERISK_USER_NAME}" >/dev/null 2>&1 && getent group "${ASTERISK_GROUP_NAME}" >/dev/null 2>&1; then
    ASTERISK_ACCOUNT_PRESENT=true
fi

# Ensure mounted directories are owned by the asterisk user on startup
if [ "${ASTERISK_ACCOUNT_PRESENT}" = true ]; then
    for target in "${CHOWN_TARGETS[@]}"; do
        case "${target}" in
            /etc/asterisk*|/var/lib/asterisk*|/var/log/asterisk*|/var/spool/asterisk*|/opt/asterisk*)
                if [ -d "${target}" ]; then
                    if chown -Rh -- "${ASTERISK_USER_NAME}:${ASTERISK_GROUP_NAME}" "${target}"; then
                        echo "Ensured ownership for ${target}"
                    else
                        echo "Warning: unable to adjust ownership for ${target}"
                    fi
                fi
                ;;
            *)
                echo "Skipping ownership change for unapproved path ${target}"
                ;;
        esac
    done
else
    echo "Warning: user/group ${ASTERISK_USER_NAME}:${ASTERISK_GROUP_NAME} not found; skipping ownership adjustments"
fi

# Restore XML documentation into bind-mounted /var/lib/asterisk if missing
DOC_TARGET_POPULATED=false
if [ -d "${DOC_TARGET_DIR}" ] && [ "$(find "${DOC_TARGET_DIR}" -mindepth 1 -maxdepth 1 -print 2>/dev/null | wc -l)" -gt 0 ]; then
    DOC_TARGET_POPULATED=true
fi

if [ -d "${DOC_STASH_DIR}" ] && [ "${DOC_TARGET_POPULATED}" = false ]; then
    echo "Restoring Asterisk documentation into ${DOC_TARGET_DIR}..."
    mkdir -p "${DOC_TARGET_DIR}"
    cp -a "${DOC_STASH_DIR}/." "${DOC_TARGET_DIR}"
    if [ "${ASTERISK_ACCOUNT_PRESENT}" = true ]; then
        chown -R "${ASTERISK_USER_NAME}:${ASTERISK_GROUP_NAME}" "${DOC_TARGET_DIR}"
    else
        echo "Warning: user/group ${ASTERISK_USER_NAME}:${ASTERISK_GROUP_NAME} not found; skipping documentation ownership adjustments"
    fi
fi

# If the mounted config directory isn't writable (common with bind mounts),
# work on a runtime copy we can modify.
if [ -f "${PJSIP_ORIGINAL}" ] && [ ! -w "${PJSIP_ORIGINAL}" ]; then
    PJSIP_WRITABLE=false
fi

if [ ! -w "${CONFIG_DIR}" ] || [ "${PJSIP_WRITABLE}" = false ]; then
    CONFIG_WRITABLE=false
fi

if [ "${CONFIG_WRITABLE}" = false ]; then
    echo "Config directory not writable, using runtime copy at ${RUNTIME_CONFIG_DIR}..."
    ACTIVE_CONFIG_DIR="${RUNTIME_CONFIG_DIR}"
    mkdir -p "${ACTIVE_CONFIG_DIR}" || { echo "Failed to create ${ACTIVE_CONFIG_DIR}"; exit 1; }
    # Copy current config without dereferencing symlinks (-P), copying contents of the directory (${CONFIG_DIR}/.)
    cp -rP "${CONFIG_DIR}/." "${ACTIVE_CONFIG_DIR}/"
    chmod -R u+w "${ACTIVE_CONFIG_DIR}"

    if [ -f "${ACTIVE_CONFIG_DIR}/asterisk.conf" ]; then
        ESCAPED_CONFIG_DIR=$(escape_for_sed "${ACTIVE_CONFIG_DIR}")
        sed -i "s#^astetcdir[[:space:]]*=>[[:space:]]*.*#astetcdir => ${ESCAPED_CONFIG_DIR}#" "${ACTIVE_CONFIG_DIR}/asterisk.conf"
    fi
fi

PJSIP_PATH="${ACTIVE_CONFIG_DIR}/pjsip.conf"

# Replace environment variables in pjsip.conf if they are set
if [ -f "${PJSIP_PATH}" ]; then
    echo "Configuring pjsip.conf with environment variables..."
    
    # Create a temporary file for modifications
    TEMP_PJSIP=$(mktemp)
    cp "${PJSIP_PATH}" "$TEMP_PJSIP"

    # Replace ASTERISK_USER
    if [ -n "${ASTERISK_USER}" ]; then
        sed -i "s/ASTERISK_USER/${ASTERISK_USER}/g" "$TEMP_PJSIP"
        echo "  - Set ASTERISK_USER"
    else
        echo "  - WARNING: ASTERISK_USER not set, using default placeholder"
    fi
    
    # Replace ASTERISK_PASSWORD
    if [ -n "${ASTERISK_PASSWORD}" ]; then
        sed -i "s/ASTERISK_PASSWORD/${ASTERISK_PASSWORD}/g" "$TEMP_PJSIP"
        echo "  - Set ASTERISK_PASSWORD"
    else
        echo "  - WARNING: ASTERISK_PASSWORD not set, using default placeholder"
    fi
    
    # Replace ASTERISK_IP
    if [ -n "${ASTERISK_IP}" ]; then
        sed -i "s/ASTERISK_IP/${ASTERISK_IP}/g" "$TEMP_PJSIP"
        echo "  - Set ASTERISK_IP"
    else
        echo "  - WARNING: ASTERISK_IP not set, using default placeholder"
    fi
    
    # Replace FRITZBOX_IP
    if [ -n "${FRITZBOX_IP}" ]; then
        sed -i "s/FRITZBOX_IP/${FRITZBOX_IP}/g" "$TEMP_PJSIP"
        echo "  - Set FRITZBOX_IP"
    else
        echo "  - WARNING: FRITZBOX_IP not set, using default placeholder"
    fi
    
    # Move the modified file back
    mv "$TEMP_PJSIP" "${PJSIP_PATH}"
    echo "pjsip.conf configuration complete."
fi

# If we had to relocate configs, ensure Asterisk reads from the runtime copy
USE_RUNTIME_CONFIG=false
CMD_IS_ASTERISK=false
RESOLVED_CMD=""

if [ "$#" -ge 1 ] && [ -n "$1" ]; then
    if command -v "$1" >/dev/null 2>&1; then
        RESOLVED_CMD=$(command -v "$1")
    else
        RESOLVED_CMD="$1"
    fi
fi

case "${RESOLVED_CMD}" in
    asterisk|*/asterisk) CMD_IS_ASTERISK=true ;;
esac

if [ "${ACTIVE_CONFIG_DIR}" != "${CONFIG_DIR}" ] && [ "${CMD_IS_ASTERISK}" = true ]; then
    if [ -f "${ACTIVE_CONFIG_DIR}/asterisk.conf" ]; then
        USE_RUNTIME_CONFIG=true
    fi
fi

if [ "${USE_RUNTIME_CONFIG}" = true ]; then
    set -- "$@" "-C" "${ACTIVE_CONFIG_DIR}/asterisk.conf"
fi

# If running as root, drop to the configured asterisk user before starting
if [ "$(id -u)" -eq 0 ] && [ "${CMD_IS_ASTERISK}" = true ]; then
    if [ "${ASTERISK_ACCOUNT_PRESENT}" = true ]; then
        exec runuser -u "${ASTERISK_USER_NAME}" -g "${ASTERISK_GROUP_NAME}" -- "$@"
    else
        echo "Error: user/group ${ASTERISK_USER_NAME}:${ASTERISK_GROUP_NAME} not found; refusing to start as root"
        exit 1
    fi
fi

# Execute the CMD passed to the container (asterisk command)
exec "$@"
