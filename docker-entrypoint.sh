#!/bin/bash
set -e

# This script runs as root to handle permissions and documentation restoration,
# then drops privileges to the asterisk user when launching Asterisk.

# Configuration
CONFIG_DIR="/etc/asterisk"
ASTERISK_USER_NAME="${ASTERISK_USER:-asterisk}"
ASTERISK_GROUP_NAME="${ASTERISK_GROUP:-asterisk}"
ASTERISK_ACCOUNT_PRESENT=false
ASTERISK_UID=""
ASTERISK_GID=""
DOC_STASH_DIR="/usr/share/asterisk-runtime/documentation"
DOC_TARGET_DIR="/var/lib/asterisk/documentation"
XMLDOC_RELOAD_RETRIES=10

# Minimum UID/GID for non-system users (system users/groups are below this threshold)
SYSTEM_UID_GID_MAX=999

show_doc_permission_error() {
    local operation=$1
    echo "ERROR: Failed to ${operation} ${DOC_TARGET_DIR}"
    echo "ERROR: The target directory is not writable. This usually happens with bind-mounted volumes."
    if [ -n "${ASTERISK_UID}" ]; then
        echo "ERROR: Please ensure the host directory has appropriate permissions or is owned by UID ${ASTERISK_UID}."
        echo "ERROR: For example: sudo chown -R ${ASTERISK_UID}:${ASTERISK_GID} ./asterisk/data"
    else
        echo "ERROR: Please ensure the host directory has appropriate permissions."
    fi
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
    ASTERISK_UID=$(id -u "${ASTERISK_USER_NAME}")
    ASTERISK_GID=$(id -g "${ASTERISK_USER_NAME}")
fi

# Dynamically detect UID/GID from mounted volumes and adjust user/group accordingly
# This prevents permission errors when using Docker volumes with different host UID/GID
DETECTED_UID=""
DETECTED_GID=""

# Try to detect UID/GID from the first available mounted directory
for check_dir in /var/lib/asterisk /etc/asterisk /var/log/asterisk /opt/asterisk; do
    if [ -d "${check_dir}" ]; then
        # Get the owner UID/GID of the directory
        DIR_OWNER=$(stat -c '%u:%g' "${check_dir}" 2>/dev/null || echo "")
        if [ -n "${DIR_OWNER}" ] && [ "${DIR_OWNER}" != "0:0" ]; then
            DETECTED_UID="${DIR_OWNER%:*}"
            DETECTED_GID="${DIR_OWNER#*:}"
            echo "Detected UID:GID ${DETECTED_UID}:${DETECTED_GID} from ${check_dir}"
            break
        fi
    fi
done

# If we detected a different UID/GID from the volume, update the asterisk user/group
if [ -n "${DETECTED_UID}" ] && [ -n "${DETECTED_GID}" ]; then
    if [ "${ASTERISK_ACCOUNT_PRESENT}" = true ]; then
        # Check if current UID/GID differs from detected
        if [ "${ASTERISK_UID}" != "${DETECTED_UID}" ] || [ "${ASTERISK_GID}" != "${DETECTED_GID}" ]; then
            echo "Adjusting asterisk user from UID:GID ${ASTERISK_UID}:${ASTERISK_GID} to ${DETECTED_UID}:${DETECTED_GID}"
            
            # Update group GID if it differs
            if [ "${ASTERISK_GID}" != "${DETECTED_GID}" ]; then
                # Check if detected GID is a system GID before any modification
                if [ "${DETECTED_GID}" -le "${SYSTEM_UID_GID_MAX}" ]; then
                    echo "ERROR: Detected GID ${DETECTED_GID} is a system group (GID <= ${SYSTEM_UID_GID_MAX})"
                    echo "ERROR: Cannot use system GID. Please use a non-system UID/GID (> ${SYSTEM_UID_GID_MAX}) for the mounted volume."
                    exit 1
                fi
                
                if getent group "${DETECTED_GID}" >/dev/null 2>&1; then
                    # GID already exists
                    EXISTING_GROUP=$(getent group "${DETECTED_GID}" | cut -d: -f1)
                    echo "WARNING: GID ${DETECTED_GID} already exists as group '${EXISTING_GROUP}', will use it"
                    # Delete old group and use the existing one
                    if getent group "${ASTERISK_GROUP_NAME}" >/dev/null 2>&1; then
                        groupdel "${ASTERISK_GROUP_NAME}" 2>/dev/null || true
                    fi
                    ASTERISK_GROUP_NAME="${EXISTING_GROUP}"
                else
                    groupmod -g "${DETECTED_GID}" "${ASTERISK_GROUP_NAME}"
                fi
                ASTERISK_GID="${DETECTED_GID}"
            fi
            
            # Update user UID if it differs
            if [ "${ASTERISK_UID}" != "${DETECTED_UID}" ]; then
                # Check if detected UID is a system UID before any modification
                if [ "${DETECTED_UID}" -le "${SYSTEM_UID_GID_MAX}" ]; then
                    echo "ERROR: Detected UID ${DETECTED_UID} is a system user (UID <= ${SYSTEM_UID_GID_MAX})"
                    echo "ERROR: Cannot use system UID. Please use a non-system UID/GID (> ${SYSTEM_UID_GID_MAX}) for the mounted volume."
                    exit 1
                fi
                
                if getent passwd "${DETECTED_UID}" >/dev/null 2>&1; then
                    # UID already exists
                    EXISTING_USER=$(getent passwd "${DETECTED_UID}" | cut -d: -f1)
                    echo "WARNING: UID ${DETECTED_UID} already exists as user '${EXISTING_USER}', will use it"
                    # Delete old user and use the existing one
                    if getent passwd "${ASTERISK_USER_NAME}" >/dev/null 2>&1; then
                        userdel "${ASTERISK_USER_NAME}" 2>/dev/null || true
                    fi
                    ASTERISK_USER_NAME="${EXISTING_USER}"
                else
                    # Check if the asterisk user has any running processes before modifying
                    if pgrep -u "${ASTERISK_USER_NAME}" >/dev/null 2>&1; then
                        echo "WARNING: User ${ASTERISK_USER_NAME} has running processes"
                        echo "WARNING: Attempting to modify UID anyway. If this fails, restart the container."
                    fi
                    if ! usermod -u "${DETECTED_UID}" -g "${ASTERISK_GROUP_NAME}" "${ASTERISK_USER_NAME}" 2>&1; then
                        echo "ERROR: Failed to modify user ${ASTERISK_USER_NAME} to UID ${DETECTED_UID}"
                        echo "ERROR: This may happen if the user has running processes or open files."
                        echo "ERROR: Please restart the container."
                        exit 1
                    fi
                fi
                ASTERISK_UID="${DETECTED_UID}"
            fi
            
            echo "Successfully adjusted to UID:GID ${ASTERISK_UID}:${ASTERISK_GID}"
        fi
    fi
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
# This must run as root to handle bind-mounted volumes with proper permissions
DOC_TARGET_POPULATED=false
if [ -d "${DOC_TARGET_DIR}" ] && [ "$(find "${DOC_TARGET_DIR}" -mindepth 1 -maxdepth 1 -print 2>/dev/null | wc -l)" -gt 0 ]; then
    DOC_TARGET_POPULATED=true
fi

if [ -d "${DOC_STASH_DIR}" ] && [ "${DOC_TARGET_POPULATED}" = false ]; then
    echo "Restoring Asterisk documentation into ${DOC_TARGET_DIR}..."
    
    # Attempt to create directory and restore documentation
    if ! mkdir -p "${DOC_TARGET_DIR}" 2>/dev/null; then
        show_doc_permission_error "create"
        exit 1
    fi
    
    if ! cp -a "${DOC_STASH_DIR}/." "${DOC_TARGET_DIR}" 2>/dev/null; then
        show_doc_permission_error "copy documentation to"
        exit 1
    fi
    
    if [ "${ASTERISK_ACCOUNT_PRESENT}" = true ]; then
        if ! chown -R "${ASTERISK_USER_NAME}:${ASTERISK_GROUP_NAME}" "${DOC_TARGET_DIR}" 2>/dev/null; then
            echo "WARNING: Failed to set ownership for ${DOC_TARGET_DIR}"
            echo "WARNING: Documentation was restored but ownership could not be adjusted."
            echo "WARNING: Asterisk may have issues accessing the documentation."
        fi
    else
        echo "Warning: user/group ${ASTERISK_USER_NAME}:${ASTERISK_GROUP_NAME} not found; skipping documentation ownership adjustments"
    fi
    
    echo "Documentation successfully restored to ${DOC_TARGET_DIR}"
fi

PJSIP_PATH="${CONFIG_DIR}/pjsip.conf"

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
    # Use cat instead of mv to avoid cross-device/permission issues
    if ! cat "$TEMP_PJSIP" > "${PJSIP_PATH}"; then
        echo "ERROR: Failed to write modified configuration to ${PJSIP_PATH}"
        echo "ERROR: Temporary file preserved at: $TEMP_PJSIP"
        exit 1
    fi
    rm -f "$TEMP_PJSIP"
    # Ensure proper ownership after modification
    if [ "${ASTERISK_ACCOUNT_PRESENT}" = true ]; then
        if ! chown "${ASTERISK_USER_NAME}:${ASTERISK_GROUP_NAME}" "${PJSIP_PATH}"; then
            echo "WARNING: Failed to set ownership for ${PJSIP_PATH}"
            echo "WARNING: Configuration file was updated but ownership adjustment failed."
        fi
    fi
    echo "pjsip.conf configuration complete."
fi

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

CLI_CONFIG_ARGS=()

# If running as root, drop to the configured asterisk user before starting Asterisk
# Note: Privileges are only dropped for the Asterisk command to ensure proper security.
# If running other commands (e.g., shell for debugging), they will execute as root.
# This is intentional to allow system administration tasks when needed.
if [ "$(id -u)" -eq 0 ] && [ "${CMD_IS_ASTERISK}" = true ]; then
    if [ "${ASTERISK_ACCOUNT_PRESENT}" = true ]; then
        ASTERISK_PID=""
        # Use gosu to drop privileges and run as the asterisk user
        gosu "${ASTERISK_USER_NAME}:${ASTERISK_GROUP_NAME}" "$@" &
        ASTERISK_PID=$!
        trap 'if [ -n "${ASTERISK_PID}" ]; then kill -TERM "${ASTERISK_PID}"; fi' TERM INT QUIT HUP

        XMLDOC_RELOADED=false
        for attempt in $(seq 1 "${XMLDOC_RELOAD_RETRIES}"); do
            if gosu "${ASTERISK_USER_NAME}:${ASTERISK_GROUP_NAME}" asterisk "${CLI_CONFIG_ARGS[@]}" -rx "core show version" >/dev/null 2>&1 && \
               gosu "${ASTERISK_USER_NAME}:${ASTERISK_GROUP_NAME}" asterisk "${CLI_CONFIG_ARGS[@]}" -rx "xmldoc reload"; then
                echo "Applied 'xmldoc reload' during startup."
                XMLDOC_RELOADED=true
                sleep 1
                break
            fi
            sleep 1
        done
        if [ "${XMLDOC_RELOADED}" = false ]; then
            echo "Warning: Unable to apply 'xmldoc reload' after ${XMLDOC_RELOAD_RETRIES} attempts."
        fi

        wait "${ASTERISK_PID}"
        EXIT_CODE=$?
        trap - TERM INT QUIT HUP
        exit "${EXIT_CODE}"
    else
        echo "Error: user/group ${ASTERISK_USER_NAME}:${ASTERISK_GROUP_NAME} not found; refusing to start as root"
        exit 1
    fi
fi

# Execute the CMD passed to the container (asterisk command)
exec "$@"
