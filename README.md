# Asterisk 20 Docker Container

This Docker setup provides a containerized Asterisk 20 instance based on Debian Bookworm, built from source using the same steps as your Asterisk 20 on Debian 12 installation guide.

## Features

- **Source Build**: Asterisk 20 is compiled from the official source tarball.
- **Lean IVR-Only Configuration**: Optimized for PJSIP-based IVR with FritzBox, using only alaw/ulaw/g722 codecs.
- **Minimal Module Footprint**: Unused channel drivers, codecs, and applications disabled at build-time and runtime.
- **Debian Bookworm Slim**: Uses a minimal base image to reduce the attack surface and image size.
- **Sample IVR Dialplan**: Default dialplan offers language selection and records calls with `MixMonitor` to `/opt/asterisk/recordings/${UNIQUEID}.wav`.
- **Persistent Storage via Named Volumes**:
  - `asterisk_config` seeds from baked config in the image into `/etc/asterisk`.
  - `asterisk_data` persists `/var/lib/asterisk` runtime data and sounds.
  - `asterisk_logs` persists `/var/log/asterisk` logs.
  - `asterisk_recordings` persists `/opt/asterisk/recordings` recordings.
- **HTTP Access to Recordings**: Built-in nginx serves `/opt/asterisk/recordings` over HTTP (default port `6000`, configurable via `.env`).
- **Non‑Root Execution**: Asterisk runs as the dedicated `asterisk` user with adjusted directory ownership and permissions.
- **History File Integration**: Asterisk CLI history is stored in a writable directory owned by the `asterisk` user.
- **Health Checks**: A Docker health check uses the Asterisk CLI to verify that the daemon is up and responsive.
- **Security Baseline**: Designed to work with a hardened `docker-compose.yml` (no-new-privileges, dropped capabilities, AppArmor profile).
- **Resource Limits**: CPU and memory constraints in `docker-compose.yml` to avoid resource exhaustion.

## Directory Structure

- Place your configuration files (e.g. `pjsip.conf`, `extensions.conf`) in `config/` before build; they will seed the `asterisk_config` volume.
- Place custom sound files and other data in `data/` before build if you want them copied into the image; runtime updates live in the `asterisk_data` volume.
- Logs are written to the `asterisk_logs` volume.

## Setup Instructions

### 1. Configure Firewall

If you are using UFW on the host, open the relevant ports for Asterisk:

```bash
sudo ufw allow 5060/tcp
sudo ufw allow 5060/udp
sudo ufw allow 10000:20000/udp
sudo ufw reload
```

For other firewalls, ensure that the same ports are allowed and forwarded correctly to the Docker host.

### 2. Clone the repository

```bash
git clone https://github.com/barrax63/asterisk.git
cd asterisk
```

### 3. Configure Environment Variables

Copy the example environment file and customize it with your settings:

```bash
cp .env.example .env
```

Edit `.env` and set your FritzBox configuration:

```bash
# FritzBox SIP Registration User
ASTERISK_USER=asterisk

# FritzBox SIP Registration Password
ASTERISK_PASSWORD=your_secret_password_here

# Asterisk Server IP Address (where this container is reachable)
ASTERISK_IP=192.168.1.100

# FritzBox IP Address
FRITZBOX_IP=192.168.1.1

# HTTP port for downloading call recordings
RECORDINGS_HTTP_PORT=6000
```

### 4. Prepare Configuration (optional)

Configuration files are pre-configured in `config/` and baked into the image; they seed the `asterisk_config` named volume on first start. If you want to customize before build, edit the files under `config/` now.

### 5. Build and Start

From within the project directory:

```bash
# Build the image (this can take up to 10 minutes since Asterisk is built from source)
docker compose build

# Start the container in the background
docker compose up -d

# Follow logs
docker compose logs -f asterisk
```

The entrypoint script will automatically configure pjsip.conf with your environment variables from `.env`.

### 6. Connect to the Asterisk CLI

To attach to the Asterisk CLI for debugging and administration:

```bash
docker compose exec asterisk asterisk -rvvvvv
```

You should see an Asterisk banner and a CLI prompt.

### 7. Customize Your IVR Dialplan

The container comes with a basic IVR dialplan in `config/extensions.conf`. Customize it for your needs:

```bash
# Edit the dialplan
vi config/extensions.conf

# Rebuild the image to include your changes
docker compose build

# Restart the container
docker compose restart asterisk
```

**Note**: The lean IVR-only configuration is pre-applied. The image includes only essential modules for PJSIP-based IVR with alaw/ulaw/g722 codecs. All configuration files (modules.conf, pjsip.conf, extensions.conf) are baked into the image at build time.

## Accessing Configuration, Data and Logs

- **Configuration files**:  
  Baked into the image from `config/` and stored in the `asterisk_config` named volume at `/etc/asterisk`. To edit at runtime, use `docker compose exec asterisk sh -c 'vi /etc/asterisk/pjsip.conf'` or `docker compose cp`.

- **Data and sound files**:  
  Persisted in the `asterisk_data` volume at `/var/lib/asterisk`. Copy files in with `docker compose cp` or edit via `docker compose exec`.

- **Log files**:  
  Persisted in the `asterisk_logs` volume at `/var/log/asterisk`. View with `docker compose logs asterisk` or by exec/cp from the volume.

- **Call recordings (MixMonitor)**:  
  The default dialplan records calls to `/opt/asterisk/recordings/${UNIQUEID}.wav`. This path is created in the image and owned by the `asterisk` user and mounted to `./asterisk/recordings`. An embedded nginx server exposes the directory over HTTP at `http://<host>:${RECORDINGS_HTTP_PORT:-6000}/` for easy downloads.

## Maintenance

### Rebuild / Upgrade

```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

This will rebuild the image from scratch and restart the container with the updated Asterisk version or configuration.

### Data and Sound Files

To add or update sound files or other data used by Asterisk:

1. Place or update the files in `data/`.
2. Ensure paths in your Asterisk configuration match where the files are located within `/var/lib/asterisk`.

## Ports Reference

| Port         | Protocol | Purpose / Notes                     |
|--------------|----------|-------------------------------------|
| 5060         | TCP      | SIP signalling                      |
| 5060         | UDP      | SIP signalling                      |
| 10000–20000  | UDP      | UDP port range used by Asterisk RTP |
| 6000         | TCP      | HTTP access to call recordings      |

Adjust these ports in `docker-compose.yml` if you use non‑default values, and make sure your firewall configuration matches.

## Security Considerations

1. **Non‑Root User**: Asterisk runs as the `asterisk` user inside the container, and core directories are owned accordingly.
2. **Dropped Capabilities**: `docker-compose.yml` uses a capability‑drop baseline to minimize privileges.
3. **AppArmor / seccomp**: Running with Docker’s default security profiles adds another layer of isolation.
4. **No New Privileges**: The security baseline can enforce `no-new-privileges` to block privilege escalation inside the container.
5. **Volumes and Permissions**: Host folders under `./asterisk` contain configuration, data and logs. Restrict access to these directories to trusted users only.
6. **Network Exposure**: Only expose SIP/RTP ports to the networks that actually need access (e.g. internal VoIP subnets, VPNs).
7. **Minimal Attack Surface**: The IVR-only build disables unused channel drivers, codecs, and applications at both build-time and runtime, significantly reducing the attack surface.

> **🔒 Security Note**: This image disables ARI, removes legacy protocols (chan_sip, IAX2), and strips voicemail/conferencing features by default.
