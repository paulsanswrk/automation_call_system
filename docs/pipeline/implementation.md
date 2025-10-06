# Trade Pipeline: Signal Sources (Discord / Telegram / Text Files) → AI → Exchange

## Overview

When a message arrives at the Go backend from a supported source (Discord via WebSocket/HTTP, Telegram webhooks, or text file uploads), the system:

1. **Persists** the message to the database (e.g., `call_catch.messages` or `call_catch.discord_messages` with a source identifier) to deduplicate by `message_id`.
2. **Analyzes** the message text with Gemini AI using `CALL2COMMAND_PROMPT`
3. **Logs** the AI request/response to `call_catch.ai_log`
4. **Validates** the AI response for required trade fields (`pair`, `direction`, `entries`)
5. **Extracts** TP/SL from the AI response (all `takeProfit` items for TPs, `stopLoss.price` for hard SL)
6. **Resolves** the channel's active subscriptions and user exchange mappings (including `position_size_type` and `position_size_value`)
7. **Fetches** the minimum order quantity and precision scale dynamically from the target exchange
8. **Places** one properly sized limit order per entry price on each mapped exchange account. (If a single TP is provided, it is natively tied to the limit order; if multiple TPs are provided, they are handled separately post-fill).
9. **Logs** every order to `call_catch.trade_actions` (one row per entry, per user account)

## Architecture

```text
Message Source: Discord / Telegram / Text Files (WebSocket or POST to Go backend)
        │
        ▼
┌─────────────────────────┐
│   MessageHandlers       │  ◄── persisted to DB, dedup check
│   (handlers/*)          │  ◄── resolves Subscriptions & Exchange Mappings
└───────────┬─────────────┘
            │ (async goroutine)
            ▼
┌─────────────────────────┐
│   TradeProcessor         │  ◄── orchestrator (Analyzes via AI once)
│   (pipeline/)            │
└─────────┬──────┬────────┘
          │      │
          ▼      ▼                       (Fan-out per user/account)
┌───────────┐  ┌───────────────────────┐
│ GeminiAI  │  │ Ephemeral OrderPlacer  │ ◄── e.g. BitUnix, Phemex
│ (ai/)     │  │ (exchange/)           │
└─────┬─────┘  └───────────┬───────────┘
      │                    │
      ▼                    ▼
┌───────────┐  ┌───────────────┐
│ ai_log    │  │ trade_actions  │
└───────────┘  └───────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `go-core/pipeline/trade_processor.go` | Pipeline orchestrator: AI → Exchange flow |
| `go-core/ai/gemini.go` | Gemini AI provider (REST API client) |
| `go-core/ai/prompt.go` | `CALL2COMMAND_PROMPT` system prompt constant |
| `go-core/exchange/bitunix.go` | BitUnix: order placement, ticker price, min qty REST methods |
| `go-core/exchange/order_request.go` | `OrderRequest`, `OrderResult`, `OrderPlacer` interface |
| `go-core/handlers/discord.go` | HTTP handler: receives Discord messages, triggers pipeline |
| `go-core/handlers/telegram.go` | HTTP handler: receives Telegram messages and triggers pipeline |
| `go-core/handlers/file_parser.go` | HTTP handler/cron: parses bulk calls from text files |
| `go-core/handlers/discord_ws.go` | WebSocket handler: persistent connection from injector |
| `go-core/models/trade_action.go` | GORM model for `call_catch.trade_actions` |
| `go-core/models/ai_log.go` | GORM model for `call_catch.ai_log` |

## TradeProcessor

```go
processor := &pipeline.TradeProcessor{
    AI:           ai.NewGeminiProvider(geminiKey, "gemini-2.5-flash"),
    DB:           db,
    SystemPrompt: ai.CALL2COMMAND_PROMPT,
    Enabled:      true,  // false = dry-run
}

signal := processor.Analyze(messageText, replyToText, discordMessageID, false)
// Then iterate through mapped user OrderPlacers and call ExecuteOnPlacer(placer, signal, ...)
```

## Database: `call_catch.trade_actions`

| Column | Type | Description |
|--------|------|-------------|
| `id` | bigint | Primary key (identity) |
| `created_at` | timestamptz | Auto-set on insert |
| `discord_message_id` | varchar(64) | Originating message ID (from Discord, Telegram, or File) |
| `ai_log_id` | bigint | AI analysis log reference |
| `action` | varchar(50) | `PLACE_ORDER`, `SKIP`, `ERROR` |
| `exchange` | varchar(50) | `bitunix` |
| `symbol` | varchar(20) | e.g. `BTCUSDT` |
| `side` | varchar(10) | `BUY` or `SELL` |
| `order_type` | varchar(10) | `LIMIT` or `MARKET` |
| `qty` | varchar(30) | Order quantity |
| `price` | varchar(30) | Order price |
| `order_id` | varchar(100) | Exchange order ID |
| `result` | jsonb | Raw API response/error |
| `request` | jsonb | Full order request sent to exchange |
| `tp_prices` | jsonb | All TP targets from AI, e.g. `[{"price":"72130"}]` |
| `sl_price` | varchar(30) | Hard stop loss price |
| `entry_index` | smallint | 0-based index of entry in the entries array |
| `notes` | text | Human-readable explanation |
| `client_id` | varchar(100) | Unique order ID (`act_<discordMessageId>_<entryIndex>`) |
| `signal` | json | Full AI response JSON for reference |

## Database: `call_catch.channels` & `channel_subscriptions`

**`channels`**: Master list of known signal channels (Discord, Telegram, etc.). Auto-populated on startup and dynamically up-serted when new messages or `channel_active` ping events arrive from the injector scripts. Real-time active connection status is tracked and broadcasted globally from the Go backend via `/api/system/ws` as `channel_heartbeat` payloads every 30 seconds.

**`channel_subscriptions`** & **`channel_exchange_mappings`**: Per-user subscription (`live`, `paper`, or `off`), their chosen exchange connections, and custom `position_size_type` settings (`min_qty`, `tp_wise_min_qty`, `usd_amount`). The message handlers resolve all users for the channel:
- Any `live` → Trade pipeline places orders on the mapped user API keys.
- Only `paper` → Trade pipeline executes in dry-run mode (`IsTest=true`).
- No subscriptions or all `off` → Trade pipeline skips execution (message is still saved).

## Database: `call_catch.position_history`

| Column | Type | Description |
|--------|------|-------------|
| `id` | bigint | Primary key (identity) |
| `discord_message_id` | varchar(64) | Originating message ID (foreign key conceptually) |
| `exchange` | varchar(50) | e.g. `bitunix`, `phemex` |
| `symbol` | varchar(20) | e.g. `BTCUSDT` |
| `status` | varchar(20) | `OPEN` or `CLOSED` |
| `realized_pnl` | varchar(50) | Last known Realized PNL |
| `created_at` | timestamptz | When the position was recognized as OPEN |
| `closed_at` | timestamptz | When the position was recognized as CLOSED |

### Position Tracking Lifecycle & Closed Position Handling

The Go backend maintains an active `Hub` that aggregates real-time futures positions from all configured exchange api keys (`BitUnix` via private channel pushes, `Phemex` via AOP).

1. **Initial Sync**: Providers fetch an initial snapshot of pending/open positions via the Exchange REST APIs. 
    - *Crucial Check*: All parsed quantities are strictly validated as `> 0`. Some exchanges (like BitUnix) retain recently closed positions in their "pending" endpoints with a `qty` of "0" or "0.00". These are systematically filtered out.
2. **Real-time Lifecycle**:
    - **Updates**: Incoming WebSocket events update in-memory positions (mark prices, unrealized PnL, leverage).
    - **Closures**: When an exchange emits an explicit `CLOSE` event (BitUnix) or broadcasts a position update where the active size falls back to `0` (Phemex), the provider immediately deletes the position from its tracked memory map.
3. **Database Reconciliation (`reconciler.go`)**:
    - The backend syncs the memory map against `call_catch.position_history`. 
    - If a tracked position unexpectedly vanishes from the internal map (meaning it was pruned in the step above), the Reconciler classifies it as "CLOSED", saves the final `realized_pnl`, and archives the DB row.
4. **UI Updates (PWA & Flutter)**: 
    - The backend broadcast an `update` WebSocket payload to clients outlining the *entire array of currently open positions* on a specific exchange. 
    - The UI drops any previous positions from that exchange and replaces them directly with the new payload payload. Closed positions physically disappear from the array gracefully, updating the UI instantly without needing a dedicated "remove" event.

## BitUnix REST Order Placement Methods (Go)

**`PlaceOrder(req OrderRequest) (*OrderResult, error)`** — POST `/api/v1/futures/trade/place_order`, returns order ID on success.

**`CancelOrder(orderId, symbol string) error`** — POST `/api/v1/futures/trade/cancel_orders`.

**`GetTickerPrice(symbol string) (string, error)`** — GET `/api/v1/futures/market/tickers`, returns current market price.

**`GetMinOrderQty(symbol string) (string, error)`** — GET `/api/v1/futures/market/trading_pairs`, returns `minTradeVolume`.

**`GetQtyPrecision(symbol string) (int, error)`** — GET `/api/v1/futures/market/trading_pairs`, returns `basePrecision`.

**`SetPositionSL(symbol, positionId, slPrice string) error`** — POST `/api/v1/futures/tpsl/position/modify_order`.

## Configuration

All configuration is via `go-core/.env`:

```env
GEMINI_API_KEY=your-gemini-api-key
GEMINI_MODEL=gemini-2.5-flash
TRADE_PIPELINE_ENABLED=true

BITUNIX_API_KEY=your-bitunix-api-key
BITUNIX_SECRET_KEY=your-bitunix-secret-key

ENCRYPTION_KEY=64-char-hex-string  # AES-256 key for decrypting exchange_accounts credentials
```

Set `TRADE_PIPELINE_ENABLED=false` for dry-run mode (AI analysis runs, but no orders are placed).

The `ENCRYPTION_KEY` is critical for multi-user order routing. When a trade signal fires, the pipeline creates ephemeral `OrderPlacer` instances by decrypting API keys from `exchange_accounts` in the database using this key. The key is a 64-character hex string representing a 32-byte AES-256 key, parsed via `crypto.ParseHexKey()`. If this key is missing or invalid, all per-user order placements will fail.

## Migration Note

> This pipeline was originally implemented in PHP (`PHP/server.php`, `PHP/src/TradeProcessor.php`). As of March 2026, it has been fully migrated to the Go backend. The PHP implementation is retained for reference but is no longer active.
