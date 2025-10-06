# Position Helper: Live Open Positions Dashboard

## Status

✅ **Deployed and operational** (March 2026)
- BitUnix provider: **active** (WebSocket + REST)
- Phemex provider: **active** (WebSocket + REST)
- PWA page: **live** at `https://act2026.mooo.com/positions`

## Overview

The Position Helper tracks open futures positions across multiple exchanges in real-time. Because exchanges typically only stream private position events when a trade or order executes, the Go backend runs a hybrid architecture: it maintains **Private WebSockets** for account events (guaranteeing exact quantities and entry prices) and **Public WebSockets** for live high-frequency mark price ticks. It then uses a high-precision `math/big` calculator to compute live Unrealized PnL locally between events. Finally, it throttles and broadcasts these living positions over a single unified WebSocket to the PWA.

## Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                       Go Backend (go-core)                      │
│                                                                 │
│  ┌──────────────────────────┐  ┌──────────────────────────┐     │
│  │ BitUnixProvider          │  │ PhemexProvider           │     │
│  │ Private WS: position,ord │  │ Private WS: aop_p.sub    │     │
│  │ Public WS: price ch (MP) │  │ Public WS: tick_p (.M)   │     │
│  │ REST: fallback           │  │ REST: fallback           │     │
│  └────────┬─────────────────┘  └────────┬─────────────────┘     │
│           └──────────┬──────────────────┘                       │
│                      ▼                                          │
│              ┌──────────────┐                                   │
│              │ PositionHub  │  ← live PnL + 1Hz broadcaster     │
│              └──────┬───────┘                                   │
│                     │ (hook)                                    │
│              ┌──────▼───────┐                                   │
│              │ Reconciler   │  ← maps discordMsgId & DB History │
│              └──────┬───────┘                                   │
│                     │                                           │
│          ┌──────────┼──────────┐                                │
│          ▼                     ▼                                │
│   GET /api/positions    WS /api/positions/ws                    │
│   (snapshot)            (live stream to PWA)                    │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
                ┌──────────────────┐
                │      PWA         │
                │  PositionsView   │
                └──────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `go-core/exchange/position.go` | Unified `Position` DTO + `PositionUpdate` message type |
| `go-core/exchange/provider.go` | `ExchangeProvider` interface (abstract contract) |
| `go-core/exchange/bitunix.go` | BitUnix: WebSocket position & order channel + REST fallback |
| `go-core/exchange/phemex.go` | Phemex: WebSocket AOP subscription + REST fallback |
| `go-core/exchange/hub.go` | `PositionHub` aggregator with client pub/sub |
| `go-core/exchange/reconciler.go` | Modifies position snapshots before broadcast, writing DB rows |
| `go-core/handlers/positions.go` | HTTP handlers for `/api/positions` and `/api/positions/ws` |
| `go-core/middleware/auth.go` | JWT auth middleware (header + query param fallback for WS) |
| `ui_app/pwa/src/views/PositionsView.vue` | PWA page with live position table |

## ExchangeProvider Interface

```go
type ExchangeProvider interface {
    Name() string
    Connect(ctx context.Context) error
    Disconnect() error
    Positions() []Position
    OnUpdate(callback func([]Position))
    OnOrder(callback func(OrderEvent))
}
```

To add a new exchange, implement this interface. The hub and API layer consume it generically — no frontend changes required.

## Unified Position DTO

```go
type Position struct {
    Exchange         string    `json:"exchange"`         // "bitunix", "phemex"
    PositionID       string    `json:"positionId"`
    Symbol           string    `json:"symbol"`           // e.g. "BTCUSDT"
    Side             string    `json:"side"`             // LONG / SHORT
    Qty              string    `json:"qty"`
    EntryPrice       string    `json:"entryPrice"`
    MarkPrice        string    `json:"markPrice"`
    Leverage         string    `json:"leverage"`
    UnrealizedPnl    string    `json:"unrealizedPnl"`
    RealizedPnl      string    `json:"realizedPnl"`
    LiquidationPrice string    `json:"liquidationPrice"`
    MarginMode       string    `json:"marginMode"`       // CROSS / ISOLATED
    Margin           string    `json:"margin"`
    DiscordMsgID     string    `json:"discordMessageId,omitempty"` // ID of the originating Call
    UpdatedAt        time.Time `json:"updatedAt"`
}
```

## BitUnix Provider

**WebSocket**: `wss://fapi.bitunix.com/private/`

**Authentication** (double SHA256):
```
digest = SHA256(nonce + timestamp + apiKey)
sign   = SHA256(digest + secretKey)
```

**Flow**:
1. REST fetch of current positions (`GET /api/v1/futures/position/get_pending_positions`)
2. Private WebSocket login → subscribe to `position` channel
3. Public WebSocket unauthenticated connection → dynamically subscribe to `price` channels for symbols with open positions
4. Receive OPEN/UPDATE/CLOSE events on private WS (merging, preserving `entryPrice`), receive mark-price (`MP`) ticks on public WS.
5. `CalculateUnrealizedPnl()` continuously processes live mark prices using `math/big` against the `entryPrice` (handling `BUY` and `SELL` direction).
6. State is flagged dirty and a `runTickBroadcast` goroutine throttles UI updates to 1 per second.

**Position events pushed on**: orders created, filled, or cancelled. Live price events poured continuously.

## Phemex Provider

**WebSocket**: `wss://phemex.com/ws`

**Authentication** (HMAC-SHA256):
```
signature = HmacSha256(apiKey + expiry, secretKey)
```

**Flow**:
1. REST fetch of current positions (`GET /g-accounts/accountPositions?currency=USDT`)
2. Private WebSocket `user.auth` → `aop_p.subscribe` (Account-Order-Position)
3. Public WebSocket unauthenticated connection → dynamically subscribe to `tick_p` for mark-price symbols (e.g. `.MBTCUSDT`).
4. Receive snapshot + incremental updates with `positions_p` array. Merge private drops to preserve `entryPrice`.
5. Apply public ticks via `CalculateUnrealizedPnl()` (handling `LONG` and `SHORT`).
6. Filter: only broadcast positions with `size > 0` and throttle via a 1Hz ticker to the PWA.

**Phemex specifics**: uses negative leverage for cross mode (absolute value taken), `posSide` mapped to LONG/SHORT. Mark price symbols are prefixed with `.M`.

## PositionHub

Central aggregator that:
- Starts all providers as concurrent goroutines
- Maintains in-memory position map keyed by exchange name
- Broadcasts `PositionUpdate` messages to connected PWA WebSocket clients
- Thread-safe (RWMutex for positions, separate mutex for client set)
- Non-blocking broadcast (slow clients are skipped)

## PositionReconciler (Isolation logic)

Because the system allows manual trading outside of the bot (e.g., clicking on the exchange app itself), the PositionReconciler strictly watches for "approved" bot orders.
1. The Reconciler listens to `OnOrder()` across all providers.
2. It parses the `clientOrderId` associated with every execution fill.
3. If it starts with `act_`, it looks up the associated `discord_message_id` in Postgres (`trade_actions`) and maps the symbol into memory.
4. When `Hub` gathers positions, it feeds them to `Reconciler.ReconcileSnapshot()`. The Reconciler writes `discord_message_id` directly onto the Position struct, ensuring frontend clients know exact origin.
5. In the same loop, it manages the Postgres `position_history` table (writing `OPEN` / `CLOSED` rows + Realized PnL updates).
6. **Post-Fill Automation**: A `FillListener` hooked into `Hub` detects newly opened positions and triggers automated order management, such as setting Stop Loss to Breakeven (after TP1 hits) and placing limit orders dynamically for multiple Take Profits.

## API Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/api/positions` | GET | JWT (header) | Current snapshot of all positions (JSON array) |
| `/api/positions/ws` | GET | JWT (query param `?token=`) | WebSocket upgrade for live streaming |

**Authentication**: The JWT middleware accepts the token from either the `Authorization: Bearer <token>` header (REST) or the `?token=<jwt>` query parameter (WebSocket). Browsers cannot send custom headers during WebSocket upgrade, so the query param fallback is essential.

**WebSocket message format**:
```json
{
  "type": "snapshot|update|remove",
  "exchange": "bitunix",
  "positions": [{ ... }]
}
```

- `snapshot` — full position list, sent on initial connect
- `update` — positions changed on one exchange (full replace for that exchange)
- `remove` — positions to delete (by positionId)

## Configuration

### Go Backend (`.env`)

```env
BITUNIX_API_KEY=your-bitunix-api-key
BITUNIX_SECRET_KEY=your-bitunix-secret-key
PHEMEX_API_KEY=your-phemex-api-key
PHEMEX_SECRET_KEY=your-phemex-secret-key
```

Providers initialize conditionally — if keys are empty/missing, the provider is skipped with a log message.

## Nginx Configuration

The HTTPS server block at `/etc/nginx/sites-enabled/act_call_catch.conf` includes a WebSocket-specific proxy block (must appear before the generic `/api/` block):

```nginx
# WebSocket proxy for position live updates
location /api/positions/ws {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 86400;
}

location /api/ {
    proxy_pass http://127.0.0.1:8080;
    ...
}
```

SSL is managed by certbot (Let's Encrypt), auto-renewing.

## PWA: PositionsView

- Fetches initial snapshot via REST (`GET /api/positions`), then connects to WebSocket for live updates
- JWT passed as `?token=` query parameter for WebSocket auth
- Responsive: table on desktop, cards on mobile
- Positions grouped by exchange with visual badges
- Summary cards: total positions count, total unrealized PnL, exchange count
- PnL color-coded (green positive / red negative)
- Connection status indicator (🟢 Live / 🟡 Connecting / 🔴 Disconnected)
- Auto-reconnect on WebSocket disconnect (3s delay)

## Build & Deploy

```bash
# Go backend
cd go-core
go build -o go-core-server .
sudo systemctl restart go-core

# PWA
cd ui_app/pwa
npm run build
# dist/ is served directly by Nginx (root points to dist/)
```

## Adding a New Exchange

1. Create `go-core/exchange/myexchange.go` implementing `ExchangeProvider`
2. Add API key fields to `config/config.go` and `.env`
3. Add conditional initialization in `main.go`:
   ```go
   if cfg.MyExchangeAPIKey != "" {
       providers = append(providers, exchange.NewMyExchangeProvider(cfg.MyExchangeAPIKey, cfg.MyExchangeSecretKey))
   }
   ```
4. No frontend changes needed — positions auto-appear in the PWA
