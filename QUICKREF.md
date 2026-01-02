# IVR-Only Asterisk Quick Reference

## What's Different?

This is a **lean, IVR-only** Asterisk build optimized for PJSIP communication with FritzBox.

### Included (Enabled)
✅ **PJSIP** - Modern SIP stack  
✅ **Codecs** - alaw, ulaw, g722 only  
✅ **IVR Apps** - Playback, Background, Read, WaitExten, Stack, Dial  
✅ **RTP** - Media/audio streaming  
✅ **Basic logging** - res_logger  

### Removed (Disabled)
❌ **Legacy protocols** - chan_sip, IAX2, MGCP, Skinny, H.323, DAHDI  
❌ **Voicemail** - app_voicemail, app_directory  
❌ **Conferencing** - ConfBridge, MeetMe  
❌ **Queues** - app_queue, agent pools  
❌ **Fax** - T.38/fax modules  
❌ **ARI/Stasis** - REST API interface  
❌ **Extra codecs** - Opus, Speex, iLBC, G.726, GSM  
❌ **Music on Hold** - MOH (can be re-enabled)  

### Optional (Commented)
🔧 **AMI** - Manager interface (enabled by default, can disable)  
🔧 **CDR/CEL** - Call logging (enabled by default, can disable)  
🔧 **SRTP** - Secure RTP (enabled by default, can disable)  
🔧 **AGI** - External scripts (disabled by default, can enable)  

## Quick Start

### 1. Build and Start
```bash
docker compose build
docker compose up -d
```

### 2. Apply IVR Configuration
```bash
# Review the modules.conf template
cat asterisk/config/modules.conf

# Restart to apply (sample configs will be generated on first start)
docker compose restart asterisk
```

### 3. Verify Setup
```bash
# Automated check
./verify-ivr-setup.sh

# Or manual check
docker compose exec asterisk asterisk -rx "core show codecs"
docker compose exec asterisk asterisk -rx "pjsip show endpoints"
```

## Configuration Files

### Essential Files to Configure
1. **pjsip.conf** - Your FritzBox trunk, endpoints, authentication
2. **extensions.conf** - Your IVR dialplan logic
3. **modules.conf** - Module loading (template provided)
4. **rtp.conf** - RTP port ranges (default 10000-20000)

Location: `./asterisk/config/` (mounted to `/etc/asterisk`)

## Common Commands

```bash
# Enter Asterisk CLI
docker compose exec asterisk asterisk -rvvv

# Check modules
asterisk -rx "module show"
asterisk -rx "module show like pjsip"

# Check codecs
asterisk -rx "core show codecs"

# PJSIP status
asterisk -rx "pjsip show endpoints"
asterisk -rx "pjsip show transports"
asterisk -rx "pjsip show aors"

# Reload configs
asterisk -rx "core reload"

# Restart container
docker compose restart asterisk
```

## Troubleshooting

### Module Not Loading?
1. Check if disabled in Dockerfile (build-time)
2. Check if noloaded in modules.conf (runtime)
3. Rebuild if needed: `docker compose build --no-cache`

### Codec Issues?
- Verify only alaw, ulaw, g722 in "core show codecs"
- Check endpoint config: `allow=!all,ulaw,alaw,g722`

### PJSIP Not Working?
- Check endpoints: `pjsip show endpoints`
- Enable debug: `pjsip set logger on`
- Check network/ports: `netstat -tulpn | grep asterisk`

### Need to Re-enable a Module?
1. **Build-time**: Remove `--disable` from Dockerfile, rebuild
2. **Runtime**: Remove/comment `noload =>` from modules.conf, restart

## Documentation

- **[README.md](README.md)** - Overview and quick start
- **[IVR_BUILD.md](IVR_BUILD.md)** - Comprehensive build/config guide
- **[asterisk/config/README.md](asterisk/config/README.md)** - Config templates info

## Module Counts

- **Build-time disabled**: 124+ modules
- **Runtime noload**: 147+ directives
- **Result**: Minimal, secure, IVR-focused Asterisk

## Security Notes

- No root execution (asterisk user)
- Dropped capabilities in docker-compose.yml
- No legacy protocols (chan_sip, IAX2, etc.)
- No dangerous apps (app_system, func_shell disabled)
- Minimal attack surface

## Support

For issues or customization:
1. Check [IVR_BUILD.md](IVR_BUILD.md) troubleshooting section
2. Review module lists in modules.conf comments
3. Enable verbose logging: `asterisk -rx "core set debug 5"`
4. Check container logs: `docker compose logs -f asterisk`
