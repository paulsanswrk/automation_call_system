# UI App — Implementation

## Prerequisites

- Node.js 20+
- Nginx with certbot
- Supabase project (`thpkiasoiifmapkoerls`)
- Google Cloud OAuth credentials

## Project Setup

```bash
cd /home/ubuntu/projects/ACT_Call_Catch/ui_app/pwa
npm install
```

### Environment Variables (`.env`)

```
VITE_SUPABASE_URL=https://thpkiasoiifmapkoerls.supabase.co
VITE_SUPABASE_ANON_KEY=<anon key>
VITE_API_BASE_URL=http://localhost:8080
```

## Google OAuth Configuration

### 1. GCP Console

Go to [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials):

1. Create **OAuth 2.0 Client ID** (type: Web application)
2. Set authorized JavaScript origins: `https://act2026.mooo.com`
3. Set authorized redirect URI: `https://thpkiasoiifmapkoerls.supabase.co/auth/v1/callback`
4. Copy the Client ID and Client Secret

### 2. Supabase Dashboard

1. Go to [Auth → Providers → Google](https://supabase.com/dashboard/project/thpkiasoiifmapkoerls/auth/providers)
2. Enable Google provider, paste Client ID + Secret
3. Go to Auth → URL Configuration → add `https://act2026.mooo.com` as redirect URL

## Go Backend (`go-core/`)

All REST data access is proxied through a Go HTTP backend using **GORM** (ORM) + **Gorilla Mux** (router). The PWA never queries Supabase PostgreSQL directly — it calls the Go API instead.

### Structure

```
go-core/
├── main.go                 ← Entrypoint: DB, exchange hub, routes, graceful shutdown
├── config/config.go        ← Loads .env (DB + exchange API keys)
├── models/
│   ├── discord_message.go  ← GORM model → call_catch.discord_messages
│   ├── trade_action.go     ← GORM model → call_catch.trade_actions
│   └── ai_log.go           ← GORM model → call_catch.ai_log
├── handlers/
│   ├── messages.go         ← HTTP handlers for messages, trade actions, AI log
│   └── positions.go        ← REST + WebSocket handlers for live positions
├── middleware/auth.go      ← JWT auth (header + ?token= query param for WS)
├── exchange/
│   ├── provider.go         ← ExchangeProvider interface (abstract)
│   ├── position.go         ← Unified Position DTO
│   ├── hub.go              ← PositionHub aggregator + pub/sub
│   ├── bitunix.go          ← BitUnix WebSocket + REST provider
│   └── phemex.go           ← Phemex WebSocket + REST provider
├── .env                    ← DB + exchange credentials (gitignored)
└── .env.example            ← Template without secrets
```

### API Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/api/health` | GET | — | Health check → `{"status":"ok"}` |
| `/api/messages` | GET | JWT | Latest 50 discord messages (by `received_at DESC`) |
| `/api/trade-actions` | GET | JWT | Latest 100 trade actions (by `created_at DESC`) |
| `/api/ai-log` | GET | JWT | Latest 50 AI log entries (by `created_at DESC`) |
| `/api/positions` | GET | JWT | Current snapshot of all open exchange positions |
| `/api/positions/ws` | GET | JWT (query `?token=`) | WebSocket upgrade for live position streaming |
| `/api/system/ws` | GET | JWT (query `?token=`) | WebSocket upgrade for global system events (e.g., channel heartbeats) |

### Database Connection

Connects to Supabase PostgreSQL via the **Supavisor transaction-mode pooler** (same as PHP handler):
- Host: `aws-1-eu-north-1.pooler.supabase.com:6543`
- Schema: `call_catch` (set via `search_path` in DSN)
- SSL required

### Running

```bash
cd go-core
go run .          # dev
./go-core-server  # compiled binary
```

## Key Implementation Details

### Supabase Client (`src/lib/supabase.ts`)

The Supabase JS client is used **only for Auth and Realtime** — not for REST data queries (those go through the Go backend). Configured with `db: { schema: 'call_catch' }` for Realtime channel subscriptions.

### Auth Flow (`src/composables/useAuth.ts`)

- **Reactive state**: `user`, `session`, `loading` refs shared across components
- `onAuthStateChange` listener keeps state in sync across tabs
- `signInWithGoogle()` triggers `supabase.auth.signInWithOAuth({ provider: 'google' })` with `redirectTo: window.location.origin`

### Route Guard (`src/router.ts`)

`beforeEach` hook checks `supabase.auth.getSession()`:
- No session → redirect to `/login`
- Has session + on `/login` → redirect to `/`

### Notification Feed (`src/views/NotificationFeed.vue`)

**Initial load**: Fetches from Go backend API:
```typescript
const API_BASE = import.meta.env.VITE_API_BASE_URL
const [msgRes, actionsRes] = await Promise.all([
  fetch(`${API_BASE}/api/messages`),
  fetch(`${API_BASE}/api/trade-actions`),
])
```

**Live updates**: Subscribes to Supabase Realtime channels (WebSocket):
```typescript
supabase.channel('discord-messages-realtime')
  .on('postgres_changes', { event: 'INSERT', schema: 'call_catch', table: 'discord_messages' }, ...)
  .on('postgres_changes', { event: 'INSERT', schema: 'call_catch', table: 'trade_actions' }, ...)
  .subscribe()
```

New messages are prepended with a slide-in animation. Trade actions are grouped by `discord_message_id` via a computed map.

### Positions Dashboard (`src/views/PositionsView.vue`)

**Initial load**: Fetches from Go backend REST API (`GET /api/positions`).

**Live updates**: Connects to Go backend WebSocket (`/api/positions/ws?token=<jwt>`):
- JWT passed as query param (browsers can't send headers on WS upgrade)
- On connect, receives a `snapshot` message with all positions
- Subsequently receives `update` messages when positions change on any exchange
- Auto-reconnect on disconnect (3s delay)

### Channels Dashboard (`src/views/ChannelsView.vue`)

**Initial load**: Fetches channel configuration and subscription statuses from Go backend REST API (`GET /api/channels`).

**Live updates**: Connects to Go backend generic System WebSocket (`/api/system/ws?token=<jwt>`):
- Receives `channel_heartbeat` broadcast payloads every 30 seconds globally to accurately visualize live WebScraper connectivity.
- Contains an internal 1-second interval to reactively increment age strings relative to the latest heartbeat without making extra API calls.
- Stale "warn" visualization icon (`pi-exclamation-triangle`) gracefully appears instantly if 60 seconds have passed without an updated WebSocket ping.

**UI features**:
- Summary cards: total position count, total unrealized PnL, exchange count
- Positions grouped by exchange with gradient badges
- Responsive: table on desktop, card layout on mobile
- PnL color-coded (green positive / red negative)
- Side badges (🟢 LONG / 🔴 SHORT)
- Connection status indicator (Live / Connecting / Disconnected)

### PWA Configuration (`vite.config.ts`)

- **registerType**: `autoUpdate` — service worker updates silently
- **Workbox**: precaches all `.js`, `.css`, `.html`, `.png`, `.svg`, `.woff2` files
- **Manifest**: `display: "standalone"`, dark theme color, maskable icons

### CSS Design System (`src/style.css`)

Custom CSS variables define the dark palette:
- `--surface-ground`: `#0f172a` (background)
- `--surface-card`: `#1e293b` (cards)
- `--primary-color`: `#6366f1` (indigo accents)

Mobile responsive: sidebar collapses to a bottom tab bar at `< 768px`.

## Supabase Migrations

### `add_rls_select_policies`

Adds `SELECT` policies for `authenticated` role on `discord_messages`, `ai_log`, and `trade_actions`.

## Hosting

### Nginx Config

Located at `/etc/nginx/sites-enabled/act_call_catch.conf`:
- Serves PWA from `ui_app/pwa/dist/` (Nginx root points to dist directly)
- SPA fallback: `try_files $uri $uri/ /index.html`
- PHP handler at `/cc` (alias to `PHP/` directory)
- WebSocket proxies: `/api/positions/ws` and `/api/system/ws` with `Upgrade` + `Connection` headers
- REST proxy: `/api/` to Go backend on `:8080`
- SSL managed by certbot (Let's Encrypt, auto-renews)
- HTTP → HTTPS redirect

### Build & Deploy

```bash
# Go backend
cd go-core
go build -o go-core-server .
sudo systemctl restart go-core

# PWA (dist/ served directly by Nginx)
cd ui_app/pwa
npm run build
```

### Dev Server

```bash
npm run dev
# Opens at http://localhost:5173
```

## Architecture: Data Flow

```
┌──────────┐    REST (fetch)    ┌───────────┐    GORM/SQL    ┌──────────────┐
│  PWA     │ ◄────────────────► │  Go API   │ ◄────────────► │  Supabase PG │
│ (Vue 3)  │                    │  :8080    │                │  call_catch  │
└──────────┘                    └───────────┘                └──────────────┘
      │                               │
      │  WebSocket (Realtime)         │  WebSocket (exchange APIs)
      └──────────────────────►│       └──────────────────────────► BitUnix
                Supabase PG   │                                    Phemex
                              │  WebSocket (positions / system)
      ◄───────────────────────┘
          /api/positions/ws
          /api/system/ws
```

- **REST reads** → Go backend (messages, trade actions, AI log, positions)
- **Realtime notifications** → Supabase JS client (live INSERT events)
- **Realtime positions** → Go backend WebSocket (`/api/positions/ws`)
- **Auth** → Supabase Auth (Google OAuth)

## Implemented Features

| Feature | Status | Description |
|---------|--------|-------------|
| Notifications | ✅ Live | Discord messages + trade actions feed |
| Web Push | ✅ Live | VAPID push notifications on new trade actions |
| Positions | ✅ Live | Live exchange position display (BitUnix and Phemex active) |

## Future Work

| Feature | Description | Key Technologies |
|---------|------------|-----------------|
| Position Helper | Place additional orders from UI | Go core order execution, `user_exchange_accounts` (encrypted) |
| Backtesting | Strategy simulation UI | Go core engine, chart library |
| Go WebSocket relay | Replace Supabase Realtime with Go `LISTEN/NOTIFY` | Phase 2+ |
