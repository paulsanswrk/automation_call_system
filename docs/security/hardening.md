# Security Hardening — ACT Call Catch

Last updated: 2026-04-05

## 1. Architecture Overview

```
Internet
   │
   ▼
┌──────────────────────────────────┐
│  nginx (HTTPS, port 443)         │
│  Let's Encrypt TLS               │
│  act2026.mooo.com                │
├──────────────────────────────────┤
│  /api/*           → 127.0.0.1:8080 (Go backend)
│  /api/positions/ws → 127.0.0.1:8080 (WebSocket, 86400s timeout)
│  /api/system/ws   → 127.0.0.1:8080 (WebSocket, 86400s timeout)
│  /ws/discord      → 127.0.0.1:8080 (WebSocket, 86400s timeout)
│  /discord/injector.js → 127.0.0.1:8080 (static JS)
│  /*               → SPA fallback (pwa/dist/index.html)
└──────────────────────────────────┘
   │
   ▼
┌──────────────────────────────────┐
│  Go Backend (127.0.0.1:8080)     │
│  NOT accessible from internet    │
└──────────────────────────────────┘
```

## 2. Firewall (ufw)

| Rule | Port | Protocol |
|------|------|----------|
| ALLOW | 22 | TCP (SSH) |
| ALLOW | 80 | TCP (HTTP → 301 redirect to HTTPS) |
| ALLOW | 443 | TCP (HTTPS) |
| **DENY** | **everything else** | — |

Port 8080 (Go server) is **not** exposed. The Go server binds to `127.0.0.1` only, and ufw blocks all non-whitelisted inbound ports.

```bash
# Check status
sudo ufw status verbose
```

## 3. Endpoint Inventory & Authentication

### Public (no auth required)

| Route | Method | Notes |
|-------|--------|-------|
| `/api/health` | GET | Returns `{"status":"ok"}` only — no internal state leaked |

### Injector Token Protected

These endpoints require `Authorization: Bearer <INJECTOR_TOKEN>` header or `?token=<INJECTOR_TOKEN>` query param:

| Route | Method | Purpose |
|-------|--------|---------|
| `/api/discord/message` | POST | Discord message ingestion (HTTP fallback) |
| `/ws/discord` | GET (WebSocket) | Discord injector persistent connection |

The `INJECTOR_TOKEN` is a 64-character hex string set in `go-core/.env`. The default is empty (rejects all requests if not configured).

### JWT Protected (Supabase Auth)

These require a valid Supabase JWT in `Authorization: Bearer <JWT>` or `?token=<JWT>`:

| Route | Method | Notes |
|-------|--------|-------|
| `/api/messages` | GET | List Discord messages |
| `/api/messages` | DELETE | Delete messages |
| `/api/messages/manual` | POST | Manual call entry |
| `/api/push/subscribe` | POST/DELETE | Push notification management |
| `/api/positions` | GET | Current positions |
| `/api/positions/ws` | GET (WebSocket) | Live position updates |
| `/api/channels` | GET/POST | Channel management |
| `/api/channels/:id/subscribe` | POST/DELETE | Channel subscriptions |
| `/api/system/ws` | GET (WebSocket) | System-wide UI updates |
| `/api/exchange-accounts` | GET/POST | Exchange account management |
| `/api/exchange-accounts/:id` | DELETE | Remove exchange account |

### JWT + Admin Role Protected

These additionally require `app_metadata.role == "admin"` in the JWT:

| Route | Method | Notes |
|-------|--------|-------|
| `/api/trade-actions` | GET/DELETE | Trade action logs |
| `/api/trade-actions/:id` | DELETE | Single trade action |
| `/api/ai-log` | GET/DELETE | AI analysis logs |
| `/api/ai-log/:id` | DELETE | Single AI log |
| `/api/channels/:id` | DELETE | Remove channel |
| `/api/push-update` | POST | Broadcast build update to all clients |

### Unauthenticated (by design)

| Route | Method | Notes |
|-------|--------|-------|
| `/discord/injector.js` | GET | Serves the injector script. Read-only, contains no secrets beyond the injector token (which is embedded for the local Chrome instance). This endpoint is not sensitive because the token is only useful from `127.0.0.1`. |

## 4. Discord Integration — Read-Only

The system **only reads** from Discord. It does **not** use a Discord bot, bot token, or Discord API for sending messages. The data flow is strictly one-directional:

```
Discord (browser UI)
   │  DOM scraping via injector script
   ▼
Insecure Chrome (--disable-web-security)
   │  WebSocket / HTTP POST
   ▼
Go Backend (127.0.0.1:8080)
   │  Persist to DB, trigger AI pipeline
   ▼
Supabase (call_catch.discord_messages)
```

### What the system does NOT do:
- ❌ Send messages to Discord channels
- ❌ Use Discord bot tokens
- ❌ Call Discord's REST API (`discord.com/api/`)
- ❌ Use the `discordgo` library or any Discord SDK

## 5. Discord Write Guard

The injector script includes a **Write Guard** that monkey-patches all browser networking APIs at load time. Any attempt by 3rd-party JavaScript (scripts, extensions, injected code) to write to Discord's API is **blocked and traced**.

### How it works

The guard patches three APIs before any other code runs:

| API | Intercepted Methods | Action on Discord write |
|-----|---------------------|------------------------|
| `window.fetch()` | POST, PUT, PATCH, DELETE | Returns `Promise.reject()` |
| `XMLHttpRequest` | POST, PUT, PATCH, DELETE | Calls `.abort()` |
| `navigator.sendBeacon()` | POST (implicit) | Returns `false` |

### What gets blocked

Any request matching `discord.com/api/` with a write method. This includes:
- Sending messages (`/channels/{id}/messages`)
- Editing messages, adding reactions
- Joining/leaving servers
- Any other Discord API mutation

### Forensic Tracing

Every blocked attempt is logged to the browser console with:
- 🚫 Method and full URL
- Source API (`fetch`, `XMLHttpRequest`, or `sendBeacon`)
- **Full stack trace** — identifies exactly which script and line attempted the write

Blocked attempts are also stored in memory for inspection:

```javascript
// In Chrome DevTools console:
window.__discordWriteGuardLog
// Returns array of { timestamp, method, url, stack, source }
```

### Limitations

- Only effective if the injector loads **before** malicious code. Since the bookmarklet is manually activated and the insecure Chrome runs without extensions, this covers the practical threat model.
- Cannot intercept writes made via WebSocket connections to Discord's gateway (but the gateway uses `wss://gateway.discord.gg`, not the REST API, and message sending via gateway is not standard).

## 6. Insecure Chrome Instance

The Discord injector requires a Chrome instance launched with `--disable-web-security` to bypass Discord's CSP and Private Network Access restrictions.

### Security implications

- All same-origin, CORS, and CSP protections are disabled in this browser
- Any script running in this browser has unrestricted access to Discord's session
- The Write Guard (§5) mitigates this by intercepting outbound writes

### Recommendations

- **Never browse other sites** in the insecure Chrome instance
- **Never install extensions** in the insecure Chrome profile
- The insecure Chrome uses a **separate profile** (`~/.chrome-insecure`) — it does not share cookies/sessions with the main browser

## 7. Encryption

| What | How | Key location |
|------|-----|--------------|
| Exchange API keys (at rest) | AES-256-GCM | `ENCRYPTION_KEY` in `.env` (64-char hex) |
| Database connection | TLS (sslmode=require) | Supabase managed |
| All HTTP traffic | TLS 1.2/1.3 via Let's Encrypt | Nginx managed, auto-renewed |
| JWT verification | JWKS (RS256 public keys) | Auto-fetched from Supabase |

## 8. Files Not Served

The following project directories are **NOT accessible** from the web:

- `/home/ubuntu/projects/ACT_Call_Catch/docs/` — not under any nginx root or alias
- `/home/ubuntu/projects/ACT_Call_Catch/go-core/` — not served (only the compiled binary runs)
- `/home/ubuntu/projects/ACT_Call_Catch/go-core/.env` — not accessible from any endpoint

Requests to paths like `/docs/...` receive the SPA fallback (`index.html`), not actual file contents.

## 9. Configuration Reference

All security-relevant environment variables in `go-core/.env`:

| Variable | Purpose | Default |
|----------|---------|---------|
| `SERVER_PORT` | Go server listen port | `8080` |
| `SERVER_BIND` | Go server bind address | `127.0.0.1` |
| `CORS_ORIGIN` | Allowed CORS origin | `*` (override in `.env`) |
| `INJECTOR_TOKEN` | Discord injector auth token | `""` (empty = reject all) |
| `ENCRYPTION_KEY` | AES-256 key for exchange credentials | `""` |
| `SUPABASE_URL` | JWKS endpoint base URL | Supabase project URL |
| `TRADE_PIPELINE_ENABLED` | Whether AI → exchange pipeline runs | `true` |

## 10. Maintenance Checklist

- [ ] **SSL certificate**: Auto-renewed by certbot. Expires 2026-06-25. Check with `sudo certbot certificates`
- [ ] **UFW**: Verify active with `sudo ufw status`
- [ ] **Go server binding**: Verify with `ss -tlnp | grep 8080` (should show `127.0.0.1:8080`)
- [ ] **Injector token**: Rotate periodically by updating both `.env` and `discord_injector.js`
- [ ] **Encryption key**: Same key must be used to decrypt existing exchange account credentials
