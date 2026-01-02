# IVR-Only Asterisk Build & Configuration Guide

This document provides detailed instructions for building, configuring, and verifying a lean IVR-only Asterisk Docker image optimized for PJSIP-based IVR operation with FritzBox.

## Overview

This configuration creates a minimal Asterisk installation focused exclusively on:
- **PJSIP signaling** to FritzBox trunk
- **IVR functionality**: Playback, DTMF collection, basic call flow
- **Codecs**: alaw, ulaw, g722 only
- **Removed/Disabled**: Voicemail, conferencing, queues, fax, legacy protocols, unused codecs, ARI/AMI (optional), CDR/CEL (optional)

## Table of Contents

1. [Build-Time Configuration (menuselect)](#build-time-configuration)
2. [Runtime Configuration (modules.conf)](#runtime-configuration)
3. [Verification Steps](#verification-steps)
4. [Customization Options](#customization-options)
5. [Troubleshooting](#troubleshooting)

---

## Build-Time Configuration

### Dockerfile menuselect Directives

The `Dockerfile` has been enhanced with extensive `menuselect` directives to disable unused modules at build time. This approach:
- Reduces Docker image size
- Prevents modules from being installed at all
- Provides a cleaner security posture

### Categories of Disabled Modules

The build process disables the following module categories via `menuselect`:

#### 1. Channel Drivers (Disabled)
All legacy and unused channel drivers are disabled, keeping only PJSIP support:
- `chan_sip` - Legacy SIP (replaced by PJSIP)
- `chan_iax2` - IAX2 protocol
- `chan_mgcp` - MGCP protocol
- `chan_skinny` - Cisco Skinny/SCCP
- `chan_unistim` - Nortel Unistim
- `chan_ooh323` - H.323 protocol
- `chan_dahdi` - DAHDI hardware (TDM/PRI)
- `chan_mobile` - Bluetooth mobile
- `chan_console` - Console/ALSA
- `chan_misdn` - mISDN
- `chan_phone` - Quicknet cards

#### 2. Codecs (Disabled)
All codecs except alaw, ulaw, and g722 are disabled:
- `codec_ilbc`, `codec_lpc10`, `codec_speex`
- `codec_opus`, `codec_silk`
- `codec_siren7`, `codec_siren14`
- `codec_g726`, `codec_adpcm`, `codec_gsm`
- `codec_resample` (use only if transcoding needed)
- `codec_dahdi`

**Kept codecs**: `codec_alaw`, `codec_ulaw`, `codec_g722`

#### 3. Format Handlers (Disabled)
Non-essential format handlers are disabled:
- `format_g719`, `format_g723`, `format_g726`, `format_g729`
- `format_siren7`, `format_siren14`
- `format_sln`, `format_vox`, `format_ilbc`
- `format_h263`, `format_h264` (video formats)
- `format_ogg_vorbis`

**Kept formats**: `format_pcm`, `format_wav`, `format_wav_gsm` (for IVR prompts)

#### 4. Applications (Disabled)
Non-IVR applications are disabled:
- Voicemail: `app_voicemail`, `app_voicemailmain`, `app_directory`, `app_minivm`
- Conferencing: `app_confbridge`, `app_meetme`
- Queues: `app_queue`, `app_agent_pool`
- Call Parking: `app_parkandannounce`, `app_parkedcall`, `res_parking`
- Fax: `app_fax`, `res_fax`, `res_fax_spandsp`
- Monitoring: `app_chanspy`, `app_mixmonitor`
- Other: `app_amd`, `app_festival`, `app_externalivr`, etc.

**Kept applications** (for IVR):
- `app_playback`, `app_background` - Audio playback
- `app_read` - DTMF input collection
- `app_waitexten`, `app_wait` - Wait for input
- `app_stack` - Gosub/Return for subroutines
- `app_dial`, `app_hangup`, `app_answer` - Basic call control
- `app_verbose`, `app_noop` - Logging
- `app_goto`, `app_gotoif` - Dialplan flow control

#### 5. Resources (Disabled)
- **ARI/Stasis**: All `res_ari_*` and `res_stasis_*` modules
- **HTTP**: `res_http_websocket`, `res_http_post` (unless needed)
- **Monitoring**: `res_hep`, `res_hep_pjsip`, `res_hep_rtcp`, `res_snmp`
- **Clustering**: `res_corosync`, `res_xmpp`
- **Music on Hold**: `res_musiconhold` (optional - can enable if needed)
- **Calendar**: All `res_calendar_*` modules
- **Database/ODBC**: `res_config_odbc`, `res_odbc`, `res_config_pgsql`, `res_config_ldap`

**Kept resources** (essential for PJSIP IVR):
- All `res_pjsip*` modules (PJSIP stack)
- `res_pjproject` - PJSIP library integration
- `res_rtp_asterisk` - RTP media handling
- `res_sorcery_*` - Configuration backend
- `res_logger` - Logging
- `res_timing_*` - Timing sources

### Modifying the Build

To customize the build, edit the `Dockerfile` and modify the `menuselect` section:

```dockerfile
# Example: Re-enable Music on Hold
# Remove or comment out the following line:
# --disable res_musiconhold \

# Example: Disable AMI
# Add the following line:
--disable manager \
```

After modifying, rebuild the image:

```bash
docker compose build --no-cache
```

---

## Runtime Configuration

Configuration files from `config/` are baked into the image and seed the `asterisk_config` named volume at `/etc/asterisk`. Runtime edits can be done via `docker compose exec asterisk`.

### modules.conf Template

A comprehensive `modules.conf` template is provided in `asterisk/config/modules.conf`. This file serves as a **runtime safeguard** to prevent loading of unused modules even if they were compiled.

### Deployment Steps

1. **First-time setup**: Start the container to generate sample configs:
   ```bash
   docker compose up -d
   docker compose logs -f asterisk
   # Wait for Asterisk to fully start
   docker compose down
   ```

2. **Deploy modules.conf**: 
   - Option A: Replace the generated modules.conf:
     ```bash
     cp asterisk/config/modules.conf asterisk/config/modules.conf.sample
     # Edit asterisk/config/modules.conf to customize as needed
     ```
   
   - Option B: If sample modules.conf exists in `asterisk/config/`, merge the noload directives from the template into your existing file.

3. **Restart and verify**:
   ```bash
   docker compose up -d
   docker compose exec asterisk asterisk -rx "module show"
   ```

### modules.conf Structure

The template includes:

1. **Channel Drivers**: Noload all except PJSIP
2. **Codecs**: Noload all except alaw, ulaw, g722
3. **Format Handlers**: Noload non-essential formats
4. **Applications**: Noload non-IVR apps, keep IVR essentials
5. **Resources**: Noload ARI, AMI (optional), HTTP, SNMP, HEP, calendar, database
6. **Optional Modules**: Comments indicating modules that can be enabled if needed (SRTP, AMI, CDR/CEL)

### Optional Modules

The following modules are **commented out** in the template, allowing you to enable/disable based on your needs:

#### SRTP/TLS Support
If your FritzBox trunk uses SRTP or TLS:
- Do **NOT** add `noload => res_srtp.so`
- Do **NOT** add `noload => res_crypto.so`
- Keep these modules loaded for encrypted media

#### AMI (Asterisk Manager Interface)
If you need AMI for monitoring or external integrations:
- Do **NOT** add `noload => manager.so`
- Keep AMI-related modules loaded

#### CDR/CEL (Call Logging)
If you need call detail records or channel events:
- Do **NOT** add noload directives for `cdr_*` and `cel_*` modules
- Keep logging modules loaded

#### AGI (Asterisk Gateway Interface)
If you use AGI scripts for dynamic IVR logic:
- Remove `noload => res_agi.so` from modules.conf
- Keep AGI support enabled

---

## Verification Steps

### Automated Verification Script

For quick verification, use the provided verification script:

```bash
# Run the automated verification
./verify-ivr-setup.sh
```

This script checks:
- Container status
- Asterisk version
- Loaded codecs (should be only alaw, ulaw, g722)
- PJSIP modules
- Absence of legacy channel drivers
- Absence of non-IVR applications
- Presence of essential IVR applications

### Manual Verification

If you prefer manual verification or need detailed inspection:

### 1. Module Verification

After starting the container, verify that only required modules are loaded:

```bash
# Connect to Asterisk CLI
docker compose exec asterisk asterisk -rvvv

# Check loaded modules (should be minimal)
module show
module show like pjsip
module show like codec
module show like app_
```

**Expected modules**:
- **PJSIP**: `res_pjsip.so`, `res_pjsip_session.so`, `res_pjsip_endpoint_identifier_*.so`, etc.
- **RTP**: `res_rtp_asterisk.so`, `res_pjsip_sdp_rtp.so`
- **Codecs**: `codec_alaw.so`, `codec_ulaw.so`, `codec_g722.so`
- **Format**: `format_pcm.so`, `format_wav.so`, `format_gsm.so`
- **Apps**: `app_playback.so`, `app_background.so`, `app_read.so`, `app_waitexten.so`, `app_stack.so`, `app_dial.so`, etc.
- **Bridge**: `bridge_simple.so`, `bridge_softmix.so`, `bridge_native_rtp.so`
- **PBX**: `pbx_config.so`

**Should NOT see**:
- `chan_sip.so`, `chan_iax2.so`, `chan_dahdi.so`
- `app_voicemail.so`, `app_queue.so`, `app_confbridge.so`
- `codec_opus.so`, `codec_speex.so`, `codec_g726.so`
- `res_ari*.so`, `res_stasis*.so` (if disabled)

### 2. Codec Verification

Check available codecs:

```bash
asterisk -rx "core show codecs"
```

**Expected output** (should show only):
- `alaw` - G.711 a-law
- `ulaw` - G.711 µ-law
- `g722` - G.722 (16 kHz wideband)

**Should NOT show**:
- `opus`, `speex`, `ilbc`, `g726`, `gsm`, `silk`, `siren7`, `siren14`

### 3. Application Verification

Check available applications:

```bash
asterisk -rx "core show applications"
```

Verify presence of IVR apps:
- `Playback`, `Background`, `Read`, `WaitExten`, `Gosub`, `Return`, `Dial`, `Hangup`, `Answer`

Verify absence of non-IVR apps:
- `VoiceMail`, `Queue`, `ConfBridge`, `MeetMe`, `Park`

### 4. PJSIP Stack Verification

Verify PJSIP is loaded and functional:

```bash
asterisk -rx "pjsip show version"
asterisk -rx "pjsip show endpoints"
asterisk -rx "pjsip show transports"
```

### 5. RTP Configuration Check

```bash
asterisk -rx "rtp show settings"
```

Verify RTP port range is configured correctly (typically 10000-20000).

### 6. Image Size Check

Compare image size with a full Asterisk build:

```bash
docker images | grep asterisk
```

A lean IVR-only build should be significantly smaller than a full-featured build.

### 7. Container Resource Usage

Monitor runtime resource usage:

```bash
docker stats asterisk
```

Verify CPU and memory usage is within expected limits.

---

## Customization Options

### Adding Back Modules

If you need to re-enable a module that was disabled:

1. **Build-time**: Remove the `--disable` directive from Dockerfile's menuselect section and rebuild
2. **Runtime**: Remove or comment the `noload =>` directive from modules.conf and restart

Example: Re-enabling Music on Hold:

```dockerfile
# In Dockerfile, remove this line:
# --disable res_musiconhold \
```

```conf
# In modules.conf, remove or comment:
# noload => res_musiconhold.so
```

```bash
docker compose build --no-cache
docker compose up -d
```

### Enabling SRTP/TLS

For secure RTP (SRTP) and TLS transport:

1. Ensure `res_srtp.so` and `res_crypto.so` are NOT noloaded in modules.conf
2. Configure TLS in `pjsip.conf`:
   ```ini
   [transport-tls]
   type=transport
   protocol=tls
   bind=0.0.0.0:5061
   cert_file=/path/to/cert.pem
   priv_key_file=/path/to/key.pem
   ```

### Enabling AMI for Monitoring

If you need AMI access:

1. Keep `manager.so` loaded (do not noload)
2. Configure AMI in `manager.conf`:
   ```ini
   [general]
   enabled = yes
   port = 5038
   bindaddr = 0.0.0.0
   
   [admin]
   secret = your_secure_password
   read = all
   write = all
   ```

### Enabling CDR/CEL Logging

For call logging:

1. Do not noload `cdr_*` and `cel_*` modules
2. Configure CDR in `cdr.conf` and CEL in `cel.conf`

---

## Troubleshooting

### Module Won't Load

If a required module fails to load:

1. Check if it was disabled at build time:
   ```bash
   docker compose exec asterisk ls -la /usr/lib/asterisk/modules/ | grep <module_name>
   ```

2. Check if it's noloaded in modules.conf:
   ```bash
   docker compose exec asterisk grep <module_name> /etc/asterisk/modules.conf
   ```

3. Check dependencies:
   ```bash
   docker compose exec asterisk asterisk -rx "module load <module_name>.so"
   # Error message will indicate missing dependencies
   ```

### PJSIP Not Working

1. Verify PJSIP modules are loaded:
   ```bash
   asterisk -rx "module show like pjsip"
   ```

2. Check PJSIP configuration:
   ```bash
   asterisk -rx "pjsip show endpoints"
   asterisk -rx "pjsip show aors"
   asterisk -rx "pjsip show auths"
   ```

3. Verify network connectivity and ports:
   ```bash
   docker compose exec asterisk netstat -tulpn | grep asterisk
   ```

### Codec Issues

If calls fail with codec negotiation errors:

1. Verify codecs are available:
   ```bash
   asterisk -rx "core show codecs"
   ```

2. Check endpoint codec configuration in `pjsip.conf`:
   ```ini
   [endpoint_template](!)
   type=endpoint
   allow=!all,ulaw,alaw,g722
   ```

3. Enable debug logging:
   ```bash
   asterisk -rx "core set debug 5"
   asterisk -rx "pjsip set logger on"
   ```

### Audio/Playback Issues

If IVR prompts don't play:

1. Verify format handlers are loaded:
   ```bash
   asterisk -rx "core show file formats"
   ```

2. Check sound file locations:
   ```bash
   docker compose exec asterisk ls -la /var/lib/asterisk/sounds/
   ```

3. Verify file permissions:
   ```bash
   docker compose exec asterisk ls -la /var/lib/asterisk/sounds/en/
   ```

4. Test playback from CLI:
   ```bash
   asterisk -rx "file convert /var/lib/asterisk/sounds/en/hello-world.wav /tmp/test.wav"
   ```

### Build Failures

If Docker build fails:

1. Check menuselect syntax in Dockerfile
2. Verify all `--disable` entries are valid module names
3. Check Asterisk version compatibility
4. Review build logs:
   ```bash
   docker compose build 2>&1 | tee build.log
   grep -i error build.log
   ```

---

## Advanced Configuration

### Minimal Build for Embedded Systems

For extremely resource-constrained environments:

1. Disable AMI and CDR/CEL
2. Disable `res_timing_pthread` (use `res_timing_timerfd`)
3. Disable additional logging modules
4. Reduce RTP port range in `rtp.conf`

### Security Hardening

Additional security measures:

1. Disable unnecessary functions in `modules.conf`:
   ```conf
   noload => func_shell.so
   noload => app_system.so
   ```

2. Enable ACLs in `pjsip.conf`:
   ```ini
   [acl_fritzbox]
   type=acl
   deny=0.0.0.0/0.0.0.0
   permit=192.168.1.1/32  ; FritzBox IP
   ```

3. Limit exposure in `docker-compose.yml`:
   ```yaml
   ports:
     - "127.0.0.1:5060:5060/tcp"  # Only local access
   ```

---

## Summary

This lean IVR-only Asterisk configuration provides:
- ✅ Minimal attack surface with disabled unused modules
- ✅ Reduced resource footprint (CPU, memory, disk)
- ✅ PJSIP-based signaling with FritzBox support
- ✅ Essential codecs: alaw, ulaw, g722
- ✅ Core IVR functionality: playback, DTMF input, call routing
- ✅ Runtime safeguards via modules.conf
- ✅ Comprehensive verification procedures

For questions or issues, refer to:
- Asterisk documentation: https://docs.asterisk.org/
- PJSIP configuration guide: https://wiki.asterisk.org/wiki/display/AST/Configuring+res_pjsip
- Repository README: [README.md](README.md)
