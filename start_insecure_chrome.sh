#!/bin/bash
# Launches a SECOND Chrome instance with web security disabled.
# Uses a separate profile so it runs alongside your existing Chrome/CRD session.
# NOTE: You will need to log into Discord in this new window.
#
# Required because Discord's CSP and browser PNA (Private Network Access)
# restrictions block communication with local servers (127.0.0.1).
# The --disable-web-security flag bypasses CORS, CSP, and PNA restrictions.

echo "Starting a separate Chrome instance with web security disabled..."
google-chrome \
  --user-data-dir="$HOME/.chrome-insecure" \
  --disable-web-security \
  --disable-site-isolation-trials \
  --disable-features=IsolateOrigins,site-per-process,PrivateNetworkAccessSendPreflights,PrivateNetworkAccessRespectPreflightResults \
  --no-first-run \
  "https://discord.com/channels/793098557715906597/796026765503758396" &

echo ""
echo "=== SETUP INSTRUCTIONS ==="
echo "1. Log into Discord in the new window (if needed)"
echo "2. Navigate to the target channel"
echo "3. Click the 'Inject' bookmarklet OR paste discord_injector.js into console (F12)"
echo "4. Check console for '[DiscordForwarder] === Script starting ===' message"
echo ""
echo "Note: The inlined bookmarklet is recommended over pasting."
echo "      Generate it with: node PHP/client/generate_bookmarklet.cjs"
