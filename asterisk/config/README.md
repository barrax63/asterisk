# Configuration Files

This directory contains the lean IVR-only Asterisk configuration files that are baked into the Docker image at build time.

## Configuration Files

### modules.conf

The `modules.conf` file provides runtime safeguards against loading unused modules. It complements the build-time module disabling in the Dockerfile with 147 `noload` directives.

**Key Features:**
- Disables all channel drivers except PJSIP
- Keeps only alaw, ulaw, g722 codecs
- Keeps PCM/WAV format handlers for IVR prompts
- Keeps IVR essentials: playback, read, dial, waitexten, stack
- Disables ARI/Stasis, SNMP, HEP, MOH, voicemail, conferencing, queues

**Optional Modules** (documented with comments):
- AMI (enabled by default)
- CDR/CEL (enabled by default)
- SRTP/crypto (enabled by default)
- AGI (disabled by default)

### pjsip.conf

Pre-configured PJSIP configuration for FritzBox SIP trunk registration. Uses environment variable placeholders that are replaced at container startup:

- `ASTERISK_USER` → `${ASTERISK_USER}` from .env
- `ASTERISK_PASSWORD` → `${ASTERISK_PASSWORD}` from .env
- `ASTERISK_IP` → `${ASTERISK_IP}` from .env
- `FRITZBOX_IP` → `${FRITZBOX_IP}` from .env

**Includes:**
- Transport configuration (UDP on port 5060)
- FritzBox registration
- Authentication
- Endpoint with g722, alaw, ulaw codecs
- AOR and identify sections

### extensions.conf

Minimal dialplan for IVR operation. Includes:
- Basic incoming call handler in `[incoming_calls]` context
- Example commented-out IVR with DTMF menu
- Placeholder for custom IVR logic

## Usage

### Customizing Configuration

To customize the configuration:

1. Edit the files in `asterisk/config/`:
   ```bash
   vi asterisk/config/extensions.conf  # Customize your IVR dialplan
   vi asterisk/config/pjsip.conf       # Adjust PJSIP settings if needed
   vi asterisk/config/modules.conf     # Enable/disable optional modules
   ```

2. Rebuild the image to bake in your changes:
   ```bash
   docker compose build
   ```

3. Start/restart the container:
   ```bash
   docker compose up -d
   ```

### Environment Variables

Set these in your `.env` file (copy from `.env.example`):

```bash
ASTERISK_USER=asterisk
ASTERISK_PASSWORD=your_secret_password_here
ASTERISK_IP=192.168.1.100
FRITZBOX_IP=192.168.1.1
```

The entrypoint script automatically replaces placeholders in pjsip.conf at container startup.

## Verification

After starting the container:

```bash
# Check loaded modules
docker compose exec asterisk asterisk -rx "module show"

# Check codecs (should show only alaw, ulaw, g722)
docker compose exec asterisk asterisk -rx "core show codecs"

# Check PJSIP registration
docker compose exec asterisk asterisk -rx "pjsip show endpoints"
docker compose exec asterisk asterisk -rx "pjsip show registrations"
```

Or use the automated verification script:
```bash
./verify-ivr-setup.sh
```

For comprehensive documentation, see [IVR_BUILD.md](../IVR_BUILD.md).
