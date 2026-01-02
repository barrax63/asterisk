# Configuration Templates

This directory contains configuration templates for the lean IVR-only Asterisk setup.

## modules.conf

The `modules.conf` file in this directory is a **template** that provides runtime safeguards against loading unused modules. It complements the build-time module disabling in the Dockerfile.

### Usage

1. **First-time setup**: When you first start the Asterisk container, it will generate sample configuration files in the mounted `/etc/asterisk` directory (which maps to `./asterisk/config` on the host).

2. **Deploy the template**: 
   - After the first container start, you can use this `modules.conf` template to replace or supplement the auto-generated `modules.conf`:
   
   ```bash
   # If you want to use the template as-is:
   docker compose down
   cp asterisk/config/modules.conf asterisk/config/modules.conf.bak  # Backup existing
   # Edit asterisk/config/modules.conf to customize
   docker compose up -d
   ```

   - Alternatively, merge the `noload` directives from this template into your existing `modules.conf`.

3. **Customize as needed**: 
   - The template includes comments for optional modules (SRTP, AMI, CDR/CEL, AGI).
   - Remove `noload` directives for modules you want to enable.
   - Add additional `noload` directives as needed.

### What This Template Does

- **Runtime safeguard**: Even if a module was compiled at build-time, this prevents it from loading at runtime
- **Explicit control**: Provides clear documentation of what's enabled/disabled
- **Easy customization**: Comments indicate which modules can be optionally enabled

### Key Sections

1. **Channel Drivers**: Disables all except PJSIP
2. **Codecs**: Keeps only alaw, ulaw, g722
3. **Format Handlers**: Keeps PCM/WAV for IVR prompts
4. **Applications**: Keeps IVR essentials (playback, read, dial, etc.)
5. **Resources**: Keeps PJSIP stack, disables ARI/AMI/HTTP/SNMP/etc.

### Important Notes

- This is a **template** - you may need to adjust it for your specific use case
- See [IVR_BUILD.md](../IVR_BUILD.md) for detailed documentation
- The Dockerfile already disables most of these modules at build-time
- This file provides an additional layer of protection and documentation

### Verification

After deploying and restarting with this modules.conf:

```bash
# Check loaded modules
docker compose exec asterisk asterisk -rx "module show"

# Check codecs
docker compose exec asterisk asterisk -rx "core show codecs"

# Check PJSIP
docker compose exec asterisk asterisk -rx "pjsip show endpoints"
```

For comprehensive verification steps, see [IVR_BUILD.md](../IVR_BUILD.md#verification-steps).
