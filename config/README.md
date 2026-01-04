# Configuration Files

This directory contains the lean IVR-only Asterisk configuration files that are baked into the Docker image at build time.

## Configuration Files

### extensions.conf

The `extensions.conf` file provides the dialplan for asterisk. It comes with a basic test dialplan that answers the call, plays beep tones and ends the call.

### pjsip.conf

Pre-configured PJSIP configuration for FritzBox SIP trunk registration. Uses environment variable placeholders that are replaced at container startup:

- `ASTERISK_USER` → `${ASTERISK_USER}` from .env
- `ASTERISK_PASSWORD` → `${ASTERISK_PASSWORD}` from .env
- `ASTERISK_IP` → `${ASTERISK_IP}` from .env
- `FRITZBOX_IP` → `${FRITZBOX_IP}` from .env

### How to replace with your own configuration files

Create a local `extensions.conf` or `pjsip.conf` on your machine and enter your dialplan. When you saved it, copy it into the container and reload the config:

```bash
docker compose cp ./extensions.conf asterisk:/etc/asterisk/extensions.conf # ... or pjsip.conf
docker compose exec asterisk asterisk -rx "dialplan reload" # If changing the extensions.conf
docker compose exec asterisk asterisk -rx "pjsip reload" # If changing the pjsip.conf
```

## Environment Variables

Set these in your `.env` file (copy from `.env.example`):

```bash
ASTERISK_USER=asterisk
ASTERISK_PASSWORD=your_secret_password_here
ASTERISK_IP=192.168.1.100
FRITZBOX_IP=192.168.1.1
```

The entrypoint script automatically replaces placeholders in pjsip.conf at container startup.

## Recordings

If your dialplan features MixMonitor recordings make sure to point them to `/opt/asterisk/recordings/`. There is a separate volume attached for it.

You can copy all recordings to your local machine using the following command:

```bash
docker compose cp asterisk:/opt/asterisk/recordings ./recordings
```

You can also copy single recordings:

```bash
docker compose exec asterisk ls -lisah /opt/asterisk/recordings # list all recordings
docker compose cp asterisk:/opt/asterisk/recordings/1767527404.1.wav ./recordings # copy 1767527404.1.wav
```

Alternatively, you can use the webpage the container exposes to download the files individually from the local network.

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
