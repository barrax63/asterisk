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

if [ ! -d "${CONFIG_DIR}" ]; then
    echo "Config directory ${CONFIG_DIR} not found."
    exit 1
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
    mkdir -p "${ACTIVE_CONFIG_DIR}"
    # Copy current config, following symlinks (-L) and copying contents of the directory (${CONFIG_DIR}/.)
    cp -rL "${CONFIG_DIR}/." "${ACTIVE_CONFIG_DIR}/"
    chmod -R u+w "${ACTIVE_CONFIG_DIR}"

    if [ -f "${ACTIVE_CONFIG_DIR}/asterisk.conf" ]; then
        ESCAPED_CONFIG_DIR=$(printf '%s' "${ACTIVE_CONFIG_DIR}" | sed 's/[\\/|&]/\\&/g')
        sed -i "s|^astetcdir[[:space:]]*=>[[:space:]]*.*|astetcdir => ${ESCAPED_CONFIG_DIR}|" "${ACTIVE_CONFIG_DIR}/asterisk.conf"
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

if [ "$#" -ge 1 ]; then
    case "$1" in
        asterisk|*/asterisk) CMD_IS_ASTERISK=true ;;
    esac
fi

if [ "${ACTIVE_CONFIG_DIR}" != "${CONFIG_DIR}" ] && [ "${CMD_IS_ASTERISK}" = true ]; then
    if [ -f "${ACTIVE_CONFIG_DIR}/asterisk.conf" ]; then
        USE_RUNTIME_CONFIG=true
    fi
fi

if [ "${USE_RUNTIME_CONFIG}" = true ]; then
    set -- "$@" "-C" "${ACTIVE_CONFIG_DIR}/asterisk.conf"
fi

# Execute the CMD passed to the container (asterisk command)
exec "$@"
