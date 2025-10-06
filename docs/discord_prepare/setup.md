# Discord Message Capture Setup

This document describes the approach used to capture incoming Discord messages and forward them to the Go backend.

## Overview

Due to Discord's strict Content Security Policy (CSP) and browser Private Network Access (PNA) restrictions, standard scripts cannot communicate with `127.0.0.1` from Discord. There are two layers of restriction:

1. **CSP `script-src`**: Blocks loading scripts from non-whitelisted origins (e.g., `127.0.0.1`) and inline scripts without a nonce
2. **PNA (Private Network Access)**: Blocks `fetch()` calls from public websites to private/loopback IPs

The solution uses:
- A **fetch-based bookmarklet** that fetches the capture script from the local Go server and executes it via `eval()` (allowed by Discord's `'unsafe-eval'` CSP directive)
- A **specialized Chrome launch mode** (`--disable-web-security`) that bypasses PNA, allowing `fetch()` calls to `127.0.0.1`

### Connection Modes

The Discord injector uses a **dual-mode** connection strategy:

1. **Primary — WebSocket** (`ws://127.0.0.1:8080/ws/discord`): Persistent bidirectional connection with heartbeat, auto-reconnect, and server acknowledgements.
2. **Fallback — HTTP POST** (`http://127.0.0.1:8080/api/discord/message`): Fire-and-forget REST call, used when the WebSocket is unavailable.

The ⚙️ button indicates the connection status:
- 🟢 Green border + "● WS" badge = WebSocket connected
- 🟡 Yellow border + "● HTTP" badge = HTTP fallback mode
- 🔴 Red border = Disconnected

### Deduplication

The capture system prevents duplicate messages at two levels:
- **Client-side**: Tracks processed message IDs in a `Set`. Persists to `localStorage` when available; falls back to in-memory-only in restricted environments (e.g., insecure Chrome).
- **Server-side**: The Go backend checks the Supabase database for duplicate `message_id` values before persisting.
- **Channel navigation**: Detects Discord channel switches and re-seeds visible message IDs instead of sending them as new.

### Channel Subscription Gating

When a message is successfully forwarded and persisted, the Go backend checks the `call_catch.channel_subscriptions` and `call_catch.channel_exchange_mappings` tables for that `channel_name`.
- If a `live` subscription exists for a user, the system decrypts their API keys and places orders on their mapped exchanges.
- If only `paper` subscriptions exist, it executes in dry-run mode.
- If no active subscriptions exist, the message is saved but the trade pipeline is skipped.
- New channels are automatically registered in the `channels` table upon first message.

### Capture Control Modal

The injector creates a floating ⚙️ button (bottom-right corner) that opens a **Discord Capture Control** modal:

- **Connection badge**: Shows current connection mode ("● WS" or "● HTTP") in the modal header.
- **Message table**: Shows the last 10 visible messages with columns: Time, Author, Content.
  - Time is formatted from Discord's `<time datetime>` attribute (e.g., `10:55 PM`).
  - Content is truncated with ellipsis; hover to see full text via tooltip.
- **Row selection**: Click any row to highlight it (blue tint).
- **Send to Handler**: Click "Send Selected to Handler" to send the selected message data to the Go backend.
- **Editable call text**: In the Message Details view, the call text is displayed in an editable textarea. Any modifications are sent to the handler when you click "Send Selected to Handler", but the original text remains unchanged in the message table.
- **Reply detection**: If a message replies to a previous post, the reply reference (author + text snippet) is extracted into a separate `reply_to_text` field — keeping it distinct from the message body.

### Log Entry Format

Each Discord message persisted to `call_catch.discord_messages` contains:

```json
{
  "message_id": "1234567890",
  "author": "grizzlies",
  "channel_name": "free-calls",
  "text_content": "Eth Short Entry: 1)2074 2)2134 ...",
  "html_content": "<span>Eth Short Entry: ...</span>",
  "message_timestamp": "2026-03-01T22:55:00.000Z",
  "reply_to_text": "Sol Short Entry: 1)86.2 ...",
  "received_at": "2026-03-01T20:55:00Z",
  "is_test": false
}
```

### WebSocket Protocol

```
Client → Server:
  { "type": "message", "data": { ...discordMessagePayload } }
  { "type": "channel_active", "data": { "channel_name": "..." } } (Sent every 2s as heartbeat)
  { "type": "pong" }

Server → Client:
  { "type": "ack", "message_id": "...", "status": "persisted|skipped|error", "trade_result": "..." }
  { "type": "ping" }
```

## Setup Steps

### 1. Start the Insecure Chrome Instance

**This step is mandatory.** The insecure Chrome instance is required for `fetch()` calls to bypass PNA restrictions when communicating with `127.0.0.1`.

```bash
./start_insecure_chrome.sh
```

This launches a separate Chrome instance with security flags disabled. It uses a dedicated profile directory so it doesn't interfere with your main browser session.

### 2. Ensure the Go Server is Running

The Go backend must be running on `:8080`. It handles:
- WebSocket connections from the injector (`/ws/discord`)
- HTTP POST ingestion (`/api/discord/message`)
- Serving the injector JS file (`/discord/injector.js`)
- Persisting messages to Supabase (`call_catch.discord_messages`)
- Triggering the AI → Exchange trade pipeline asynchronously

```bash
cd go-core
./go-core-server
```

Or via systemd:
```bash
sudo systemctl start go-core
```

### 3. Inject the Script

Use **one** of the following methods in the insecure Chrome window:

#### Method A: Use the Bookmarklet (Recommended)

The bookmarklet fetches `discord_injector.js` from the Go server via `fetch()` and executes it with indirect eval. It includes a cache-busting query parameter, so it always loads the latest version.

1. Generate the bookmarklet (only needed once, or if changing the server URL):
   ```bash
   node PHP/client/generate_bookmarklet.cjs
   ```
2. Copy the contents of `PHP/client/bookmarklet.txt`
3. Create a new bookmark in Chrome
4. Name it "Inject" (or "Discord Capture")
5. Paste the copied text into the **URL** field
6. Navigate to the Discord channel in the insecure Chrome window
7. Click the bookmark to inject the script

#### Method B: Paste in Console

1. Open Developer Tools (**F12** or **Ctrl+Shift+I**)
2. Go to the **Console** tab
3. Copy the entire content of `PHP/client/discord_injector.js`
4. Paste it into the console and press Enter

### Important Notes

- **Always use the insecure Chrome instance.** The bookmarklet needs `--disable-web-security` to bypass PNA for both fetching the script and sending captured messages to the backend.
- **No regeneration needed after editing `discord_injector.js`** — the bookmarklet fetches it fresh from the server each time (with cache-busting).
- **Only regenerate** if you change the server URL:
  ```bash
  node PHP/client/generate_bookmarklet.cjs
  ```
- **`localStorage` may be unavailable** in the insecure Chrome instance. The script handles this gracefully — persistence across reloads won't work, but in-session deduplication and server-side deduplication still apply.

## Verification

You should see the following in the console:
- `[DiscordForwarder] === Script starting ===`
- `[DiscordForwarder] GO_WS_URL: ws://127.0.0.1:8080/ws/discord`
- `[DiscordForwarder] Connecting WebSocket...`
- `[DiscordForwarder] WebSocket connected ✓`
- `[DiscordForwarder] Chat scroller found. Starting MutationObserver + polling...`
- `[DiscordForwarder] Seeded Y new message IDs (total tracked: Z).`

When switching channels:
- `[DiscordForwarder] Channel changed: /old/path → /new/path`

New messages will appear in the console logs and be persisted to `call_catch.discord_messages` via the Go backend.

To verify the modal UI:
1. Click the ⚙️ button (bottom-right) to open the modal
2. Check the connection badge shows "● WS" (green) or "● HTTP" (yellow)
3. Check that the Time column shows clean `HH:MM AM/PM` format
4. Hover over truncated content to see the full text tooltip
5. Click a table row (should highlight in blue), then click "Send Selected to Handler"
6. Click the × button to close the modal

## Troubleshooting

### "Permission was denied for this request to access the loopback address space"
You are not using the insecure Chrome instance. Run `./start_insecure_chrome.sh` and use that browser window.

### "Script already running!"
The injector is already loaded. Refresh the page if you need to restart it.

### "Load failed" alert from bookmarklet
The fetch to `127.0.0.1:8080` failed. Check that the Go server is running:
```bash
curl -s http://127.0.0.1:8080/discord/injector.js | head -1
```

### WebSocket won't connect (yellow badge instead of green)
1. Check that the Go server is running: `curl http://127.0.0.1:8080/api/health`
2. The injector will auto-reconnect with exponential backoff (1s → 2s → 4s → max 30s)
3. HTTP POST fallback is used automatically while WebSocket is down

### No messages appearing in database
1. Check that the Go server is running on `:8080`
2. Check the browser console for network errors
3. Check Go server logs: `journalctl -u go-core -f`

### Duplicate messages in log
The server-side dedup uses the Supabase database (`message_id` unique constraint). If a duplicate is detected, the message is skipped entirely.

## Files Reference

- `start_insecure_chrome.sh`: Launcher for the insecure Chrome instance.
- `PHP/client/discord_injector.js`: The JavaScript capture script (WebSocket + HTTP fallback, MutationObserver + polling).
- `PHP/client/bookmarklet.txt`: The generated fetch-based bookmarklet (~189 bytes).
- `PHP/client/generate_bookmarklet.cjs`: Script to regenerate the bookmarklet.
- `go-core/handlers/discord.go`: The Go backend handler for `POST /api/discord/message`.
- `go-core/handlers/discord_ws.go`: The Go backend WebSocket hub for `GET /ws/discord`.
- `go-core/pipeline/trade_processor.go`: Orchestrates AI analysis and exchange order placement.
