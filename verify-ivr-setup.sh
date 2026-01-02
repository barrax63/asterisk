#!/bin/bash
#
# verify-ivr-setup.sh - Verification script for IVR-only Asterisk configuration
#
# This script checks that the Asterisk container is properly configured for
# IVR-only operation with minimal modules loaded.
#
# Usage: ./verify-ivr-setup.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}IVR-Only Asterisk Verification Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check if container is running
echo -e "${BLUE}[1/7] Checking if Asterisk container is running...${NC}"
if docker compose ps asterisk | grep -q "Up"; then
    echo -e "${GREEN}✓ Container is running${NC}"
else
    echo -e "${RED}✗ Container is not running. Please start it with: docker compose up -d${NC}"
    exit 1
fi
echo

# Check Asterisk version
echo -e "${BLUE}[2/7] Checking Asterisk version...${NC}"
VERSION=$(docker compose exec -T asterisk asterisk -rx "core show version" 2>/dev/null | head -1)
if [ -n "$VERSION" ]; then
    echo -e "${GREEN}✓ $VERSION${NC}"
else
    echo -e "${RED}✗ Could not retrieve Asterisk version${NC}"
    exit 1
fi
echo

# Check loaded codecs
echo -e "${BLUE}[3/7] Checking loaded codecs...${NC}"
CODECS=$(docker compose exec -T asterisk asterisk -rx "core show codecs" 2>/dev/null | grep -E "(alaw|ulaw|g722)" | awk '{print $2}' | sort | uniq)
EXPECTED_CODECS="alaw g722 ulaw"

echo "Expected codecs: alaw, ulaw, g722"
echo "Loaded codecs:"
echo "$CODECS"

CODEC_COUNT=$(echo "$CODECS" | wc -l)
if [ "$CODEC_COUNT" -eq 3 ] && echo "$CODECS" | grep -q "alaw" && echo "$CODECS" | grep -q "ulaw" && echo "$CODECS" | grep -q "g722"; then
    echo -e "${GREEN}✓ Only required codecs are loaded${NC}"
else
    echo -e "${YELLOW}⚠ Codec configuration may differ from expected${NC}"
fi

# Check for unwanted codecs
UNWANTED=$(docker compose exec -T asterisk asterisk -rx "core show codecs" 2>/dev/null | grep -E "(opus|speex|ilbc|g726|gsm)" || true)
if [ -z "$UNWANTED" ]; then
    echo -e "${GREEN}✓ No unwanted codecs detected${NC}"
else
    echo -e "${YELLOW}⚠ Unwanted codecs detected:${NC}"
    echo "$UNWANTED"
fi
echo

# Check PJSIP modules
echo -e "${BLUE}[4/7] Checking PJSIP modules...${NC}"
PJSIP_MODULES=$(docker compose exec -T asterisk asterisk -rx "module show like pjsip" 2>/dev/null | grep -c "res_pjsip" || echo "0")
if [ "$PJSIP_MODULES" -gt 5 ]; then
    echo -e "${GREEN}✓ PJSIP modules loaded ($PJSIP_MODULES modules)${NC}"
else
    echo -e "${RED}✗ PJSIP modules not properly loaded${NC}"
fi
echo

# Check for legacy channel drivers
echo -e "${BLUE}[5/7] Checking for legacy channel drivers (should not be loaded)...${NC}"
LEGACY_CHANNELS=$(docker compose exec -T asterisk asterisk -rx "module show" 2>/dev/null | grep -E "(chan_sip|chan_iax2|chan_mgcp|chan_skinny|chan_dahdi)" || true)
if [ -z "$LEGACY_CHANNELS" ]; then
    echo -e "${GREEN}✓ No legacy channel drivers loaded${NC}"
else
    echo -e "${RED}✗ Legacy channel drivers detected:${NC}"
    echo "$LEGACY_CHANNELS"
fi
echo

# Check for unwanted applications
echo -e "${BLUE}[6/7] Checking for non-IVR applications (should not be loaded)...${NC}"
UNWANTED_APPS=$(docker compose exec -T asterisk asterisk -rx "module show" 2>/dev/null | grep -E "(app_voicemail|app_queue|app_confbridge|app_meetme|app_fax)" || true)
if [ -z "$UNWANTED_APPS" ]; then
    echo -e "${GREEN}✓ No unwanted applications loaded${NC}"
else
    echo -e "${YELLOW}⚠ Unwanted applications detected:${NC}"
    echo "$UNWANTED_APPS"
fi
echo

# Check for IVR essential applications
echo -e "${BLUE}[7/7] Checking for IVR essential applications...${NC}"
ESSENTIAL_APPS="app_playback app_background app_read app_stack app_dial"
MISSING_APPS=""

for app in $ESSENTIAL_APPS; do
    if ! docker compose exec -T asterisk asterisk -rx "module show like $app" 2>/dev/null | grep -q "$app"; then
        MISSING_APPS="$MISSING_APPS $app"
    fi
done

if [ -z "$MISSING_APPS" ]; then
    echo -e "${GREEN}✓ All essential IVR applications are loaded${NC}"
else
    echo -e "${RED}✗ Missing essential applications:${NC}"
    echo "$MISSING_APPS"
fi
echo

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}========================================${NC}"

# Generate module count
TOTAL_MODULES=$(docker compose exec -T asterisk asterisk -rx "module show" 2>/dev/null | grep -c "\.so" || echo "0")
echo "Total modules loaded: $TOTAL_MODULES"
echo

# Final recommendation
if [ "$CODEC_COUNT" -eq 3 ] && [ -z "$LEGACY_CHANNELS" ] && [ -z "$MISSING_APPS" ]; then
    echo -e "${GREEN}✓ Verification PASSED${NC}"
    echo -e "${GREEN}Your IVR-only Asterisk setup appears to be correctly configured.${NC}"
else
    echo -e "${YELLOW}⚠ Verification completed with warnings${NC}"
    echo -e "${YELLOW}Review the output above for details. You may want to:${NC}"
    echo "  - Check modules.conf for proper noload directives"
    echo "  - Rebuild the image if build-time modules are incorrect"
    echo "  - Restart the container after configuration changes"
fi
echo

echo "For detailed verification steps and troubleshooting, see:"
echo "  IVR_BUILD.md - Sections on Verification and Troubleshooting"
echo
