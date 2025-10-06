# Go Backend (`go-core/`)

## Overview

The Go backend is the core server for the ACT Call Catch system. It handles:

- **REST API** for the PWA (messages, trade actions, AI logs, positions)
- **Discord message ingestion** (POST endpoint + WebSocket)
- **Trade pipeline** (Gemini AI analysis → Multi-exchange order placement)
- **Position tracking** (WebSocket streaming from BitUnix and Phemex)
- **Authentication** (JWT verification via Supabase JWKS)

## Tech Stack

| Component | Library | Purpose |
|-----------|---------|---------|
| ORM | [GORM](https://gorm.io/) v1.31 | Database queries, model mapping |
| Router | [Gin](https://github.com/gin-gonic/gin) v1.12 | HTTP routing + middleware |
| CORS | [gin-contrib/cors](https://github.com/gin-contrib/cors) v1.7 | Cross-origin access for PWA |
| Auth | [golang-jwt](https://github.com/golang-jwt/jwt) v5 + [keyfunc](https://github.com/MicahParks/keyfunc) v3 | JWT verification via JWKS |
| WebSocket | [gorilla/websocket](https://github.com/gorilla/websocket) v1.5 | Position streaming + Discord |
| Config | [godotenv](https://github.com/joho/godotenv) v1.5 | `.env` file loading |
| DB driver | [pgx](https://github.com/jackc/pgx) v5 (via GORM) | PostgreSQL wire protocol |

## Project Structure

```
go-core/
├── main.go                    ← Entrypoint: all wiring (DB, JWKS, routes, pipeline, hubs)
├── config/
│   └── config.go              ← Loads .env, builds DSN string
├── ai/
│   ├── gemini.go              ← Gemini AI provider (REST API client, JSON extraction)
│   └── prompt.go              ← CALL2COMMAND_PROMPT system prompt constant
├── pipeline/
│   └── trade_processor.go     ← Trade pipeline orchestrator (AI → Exchange)
├── exchange/
│   ├── provider.go            ← ExchangeProvider interface (WebSocket position tracking)
│   ├── order_request.go       ← OrderPlacer interface + OrderRequest/OrderResult DTOs
│   ├── bitunix.go             ← BitUnix: WS positions + REST order placement
│   ├── phemex.go              ← Phemex: WS position tracking
│   ├── hub.go                 ← PositionHub aggregator with client pub/sub
│   ├── reconciler.go          ← Maps bot orders → Discord messages, position_history
│   └── position.go            ← Unified Position DTO
├── handlers/
│   ├── handler.go             ← Base Handler with DB dependency
│   ├── messages.go            ← GET handlers for messages, trade-actions, ai-log
│   ├── positions.go           ← Position REST + WebSocket handler
│   ├── discord.go             ← POST /api/discord/message (message ingestion)
│   └── discord_ws.go          ← GET /ws/discord (WebSocket hub for Discord injector)
├── models/
│   ├── discord_message.go     ← call_catch.discord_messages
│   ├── trade_action.go        ← call_catch.trade_actions
│   ├── ai_log.go              ← call_catch.ai_log
│   └── push_subscription.go   ← call_catch.push_subscriptions
├── middleware/
│   └── auth.go                ← JWT verification via Supabase JWKS + AdminOnly
├── .env                       ← Credentials (gitignored)
├── go.mod / go.sum            ← Module definition + dependency lock
└── go-core-server             ← Compiled binary
```

## API Endpoints

### Public Routes (no auth)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check → `{status, discord_ws_clients, trade_pipeline}` |
| `/api/discord/message` | POST | Discord message ingestion (replaces PHP server.php) |
| `/ws/discord` | GET | WebSocket for Discord injector (heartbeat + ack) |
| `/discord/injector.js` | GET | Static file: serves the Discord injector JS |

### Protected Routes (JWT required)

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/api/messages` | GET | JWT | Latest 50 discord messages |
| `/api/positions` | GET | JWT | Current snapshot of all exchange positions |
| `/api/positions/ws` | GET | JWT (query) | WebSocket for live position streaming |
| `/api/system/ws` | GET | JWT (query) | WebSocket for generic system events (channel heartbeats) |
| `/api/push/subscribe` | POST | JWT | Save push subscription |
| `/api/push/subscribe` | DELETE | JWT | Remove push subscription |

### Admin Routes (JWT + admin role)

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/api/trade-actions` | GET | Admin | Latest 100 trade actions |
| `/api/trade-actions/:id` | DELETE | Admin | Delete a trade action |
| `/api/ai-log` | GET | Admin | Latest 50 AI log entries |
| `/api/ai-log/:id` | DELETE | Admin | Delete an AI log entry |

## Database Connection

Connects to Supabase PostgreSQL via the **Supavisor transaction-mode pooler**:

```
Host:     aws-1-eu-north-1.pooler.supabase.com
Port:     6543
DB:       postgres
Schema:   call_catch (via search_path in DSN)
SSL:      required
```

> **Key detail**: `PreferSimpleProtocol: true` is set in the GORM Postgres config. The transaction-mode pooler does not persist prepared statements across connections in the pool, which causes `prepared statement already exists` errors with pgx's default behavior. Simple protocol sends raw SQL on each query, avoiding this.

## Configuration (`.env`)

```bash
# Database
DB_HOST=aws-1-eu-north-1.pooler.supabase.com
DB_PORT=6543
DB_NAME=postgres
DB_USER=postgres.thpkiasoiifmapkoerls
DB_PASSWORD=<your-db-password>
DB_SEARCH_PATH=call_catch

# Server
SERVER_PORT=8080
CORS_ORIGIN=https://act2026.mooo.com

# Auth
SUPABASE_URL=https://thpkiasoiifmapkoerls.supabase.co

# Gemini AI
GEMINI_API_KEY=<your-gemini-api-key>
GEMINI_MODEL=gemini-2.5-flash
TRADE_PIPELINE_ENABLED=true

# Exchange API Keys
BITUNIX_API_KEY=<your-bitunix-api-key>
BITUNIX_SECRET_KEY=<your-bitunix-secret-key>
PHEMEX_API_KEY=<your-phemex-api-key>
PHEMEX_SECRET_KEY=<your-phemex-secret-key>
```

## Subsystems

### Trade Pipeline (Discord → AI → Exchange)

When a Discord message arrives (via POST or WebSocket), the `TradeProcessor` runs asynchronously:
1. Calls Gemini AI with `CALL2COMMAND_PROMPT` + message text
2. Logs to `ai_log` table
3. Validates for required trade fields (pair, direction, entries)
4. Fans out to all mapped user exchange accounts (BitUnix, Phemex) and places limit orders
5. Logs each action to `trade_actions` (with `exchange_account_id`)

See: `docs/pipeline/implementation.md`

### Position Tracking (WebSocket Hub)

Real-time position tracking from BitUnix and Phemex via WebSocket, with live PnL calculation and 1Hz broadcast to the PWA.

See: `docs/go_backend/position_helper.md`

### Discord WebSocket Hub

Persistent bidirectional connection for the Discord injector:
- Server sends `ping` every 30s; client responds with `pong`
- Messages are acknowledged with `{type: "ack", message_id, status, trade_result}`
- Multiple injector clients supported simultaneously

## GORM Models

Each model sets a custom `TableName()` to target the `call_catch` schema explicitly:

```go
func (DiscordMessage) TableName() string {
    return "call_catch.discord_messages"
}
```

Fields use pointer types (`*string`, `*bool`) for nullable columns, and `json.RawMessage` for JSONB columns like `result`, `signal`, and `tp_prices`.

## Deployment

### Systemd Service

The Go API runs as a systemd service (`go-core.service`):

```bash
# Status
sudo systemctl status go-core

# Restart (after rebuilding)
sudo systemctl restart go-core

# Logs
journalctl -u go-core -f
```

Service file: `/etc/systemd/system/go-core.service`

### Nginx Reverse Proxy

Nginx at `act2026.mooo.com` proxies requests to the Go server:

```nginx
# WebSocket proxies (must appear before /api/)
location /api/positions/ws {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 86400;
}

location /api/system/ws {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 86400;
}

location /api/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

> **Note**: The Discord injector connects directly to `127.0.0.1:8080` (not through Nginx) since it runs on the same machine via the insecure Chrome instance.

### Build & Deploy

```bash
cd /home/ubuntu/projects/ACT_Call_Catch/go-core

# Build
go build -o go-core-server .

# Restart service
sudo systemctl restart go-core
```

### Dev Server

```bash
cd go-core
go run .
# Starts on http://localhost:8080
```

## How the PWA Uses It

The PWA's `NotificationFeed.vue` fetches initial data from the Go API:

```typescript
const API_BASE = import.meta.env.VITE_API_BASE_URL ?? ''
const [msgRes, actionsRes] = await Promise.all([
  fetch(`${API_BASE}/api/messages`),
  fetch(`${API_BASE}/api/trade-actions`),
])
```

In production, `VITE_API_BASE_URL` is empty — requests go to the same origin (`act2026.mooo.com/api/...`) and Nginx proxies them to Go.

Supabase **Realtime** (WebSocket) remains in the PWA for live INSERT notifications — the Go backend handles REST reads, position streaming, and Discord ingestion.
