# Exchange Integration: Provider Abstraction & Crypto Exchange Access

## Overview

The Exchange subsystem provides a uniform interface for interacting with crypto futures exchanges. It has two layers:

1. **Position tracking** (WebSocket-based): Real-time position and order streaming via `ExchangeProvider` interface — implemented for both BitUnix and Phemex (see `docs/go_backend/position_helper.md`)
2. **Order placement** (REST-based): Trade execution via `OrderPlacer` interface — implemented for both BitUnix and Phemex

## Architecture

```
Application Code (TradeProcessor)
        │
        ▼
┌───────────────────────────┐
│  OrderPlacer interface     │  ◄── REST order placement (Ephemeral)
└───────────┬───────────────┘
            │ implements
            ▼
┌───────────────────────────┐
│  BitUnix / Phemex         │  ◄── Dynamic provider per mapped user account
└───────────┬───────────────┘
            │ returns
            ▼
┌───────────────────────────┐
│  OrderRequest / OrderResult│  ◄── DTOs for order placement
└───────────────────────────┘
```

## Files

### Exchange Provider Layer

| File | Purpose |
|------|---------|
| `go-core/exchange/provider.go` | `ExchangeProvider` interface (WebSocket position tracking) |
| `go-core/exchange/order_request.go` | `OrderPlacer` interface + `OrderRequest`, `OrderResult` DTOs |
| `go-core/exchange/order.go` | `OrderEvent` struct for WebSocket order channel events |
| `go-core/exchange/bitunix.go` | BitUnix: WebSocket position/order channels + REST order placement |
| `go-core/exchange/phemex.go` | Phemex: WebSocket position tracking (no order placement) |
| `go-core/exchange/hub.go` | `PositionHub` aggregator with client pub/sub |
| `go-core/exchange/reconciler.go` | Maps bot orders to Discord messages, manages `position_history` |
| `go-core/exchange/position.go` | Unified `Position` DTO |
| `go-core/exchange/pnl.go` | `CalculateUnrealizedPnl` helper |

### Exchange Account Management (User API Keys)

| File | Purpose |
|------|---------|
| `go-core/crypto/crypto.go` | AES-256-GCM encrypt/decrypt utilities + hex key parser |
| `go-core/models/exchange_account.go` | GORM model `ExchangeAccount` + masked response DTO |
| `go-core/handlers/exchange_accounts.go` | CRUD handler (list/create/delete user exchange accounts) |

### Legacy PHP Files (retained for reference)

| File | Purpose |
|------|---------|
| `PHP/src/Exchange/ExchangeProviderInterface.php` | Abstract interface (now superseded by Go) |
| `PHP/src/Exchange/DTO/` | Position, Order, OrderRequest, OrderResult value objects |
| `PHP/src/Exchange/BitUnixProvider.php` | BitUnix REST implementation (now superseded by Go) |

## OrderPlacer Interface (Go)

```go
type OrderPlacer interface {
    PlaceOrder(req OrderRequest) (*OrderResult, error)
    CancelOrder(orderId, symbol string) error
    GetTickerPrice(symbol string) (string, error)
    GetMinOrderQty(symbol string) (string, error)
    GetQtyPrecision(symbol string) (int, error)
    GetAccountID() int64
    
    // Conditional Orders (for TP/SL triggers)
    PlaceTPSLOrder(req OrderRequest) (*OrderResult, error)
    CancelTPSLOrder(symbol, orderId string) error

    // Modify/Set Stop loss for an existing position
    SetPositionSL(symbol, positionId, slPrice string) error
}
```

This is separate from `ExchangeProvider` so that position-only providers (like Phemex) aren't forced to implement order placement methods. BitUnix implements both interfaces.

## DTOs

### OrderRequest
Input for placing orders:
```go
type OrderRequest struct {
    Symbol     string   // e.g. "BTCUSDT"
    Side       string   // BUY or SELL
    OrderType  string   // LIMIT, MARKET, STOP, etc.
    Qty        string   // Order quantity
    Price      *string  // Required for LIMIT orders
    Effect     string   // GTC, IOC, FOK, POST_ONLY
    TradeSide  *string  // OPEN or CLOSE (hedge mode)
    ReduceOnly bool
    ClientID   *string  // Custom order ID for reconciliation
    TpPrice    *string  // Native take-profit logic params
    SlPrice    *string  // Native stop-loss logic params
    TpQty      *string  // Optional partial scale sizes for TPs (primarily Bitunix conditional)
    StopPx     *string  // Stop price triggers (primarily Phemex Stop orders)
}
```

### Conditional TP/SL Orders

Multi-TP and Auto-SL strategies use standard execution endpoints modified to lay conditional orders correctly onto the exchanges:
- **Phemex**: Employs standing `ReduceOnly` Limit orders for TP scales, while `SetPositionSL` constructs explicit `OrderType: STOP` requests containing `StopPx` triggers attached to `posSide: Merged`.
- **BitUnix**: For TP arrays, directly utilizes the `/api/v1/futures/tpsl/place_order` API via `PlaceTPSLOrder(req)` dynamically passing explicit combinations of `tpPrice` and `tpQty`, guaranteeing execution independently from generic books.

### Order Tracking & Scaling Recalculation

`FillListener.processMultipleTPs` dynamically watches positional footprint sizes over consecutive entries. When partial fills increase the global `pos.Qty`, the script loops to cancel preceding stale TPs attached to smaller base sizes computationally via `CancelTPSLOrder`, recalculates perfect geometric fractions accounting accurately for remainders against minimum precisions, and re-submits the exact trailing structure flawlessly.

### OrderResult
Response from order placement:
```go
type OrderResult struct {
    Success bool
    OrderID string                    // Exchange order ID
    Message string                    // Error message (if failed)
    RawData map[string]interface{}    // Raw API response
}
```

## BitUnix Provider (Go)

The `BitUnixProvider` in `go-core/exchange/bitunix.go` serves dual purposes:

### WebSocket Position Tracking (ExchangeProvider)
- Private WS: `position` and `order` channels for account events
- Public WS: `price` channels for live mark-price ticks
- REST fallback: `GET /api/v1/futures/position/get_pending_positions`

### REST Order Placement (OrderPlacer)

**Authentication:** Double SHA256 signature:
```
digest = SHA256(nonce + timestamp + apiKey + queryString + bodyString)
sign   = SHA256(digest + secretKey)
```

**Headers:** `api-key`, `nonce`, `timestamp`, `sign`, `Content-Type: application/json`

**Endpoints:**

| Method | Endpoint | Go Method |
|--------|----------|-----------|
| GET | `/api/v1/futures/position/get_pending_positions` | `Positions()` (via WS) |
| POST | `/api/v1/futures/trade/place_order` | `PlaceOrder()` |
| POST | `/api/v1/futures/trade/cancel_orders` | `CancelOrder()` |
| GET | `/api/v1/futures/market/tickers` | `GetTickerPrice()` |
| GET | `/api/v1/futures/market/trading_pairs` | `GetMinOrderQty()` |

**Cancel body format** — `orderList` must be an array of objects:
```json
{"symbol": "BTCUSDT", "orderList": [{"orderId": "123456"}]}
```

**Important notes:**
- Read endpoints (`GetTickerPrice`, `GetMinOrderQty`) must use **GET**, not POST — POST returns "Network Error".
- BitUnix enforces a **minimum buy price** (~50% of current market price). Orders priced too far below market are rejected.

**Usage:**
```go
bitunix := exchange.NewBitUnixProvider(apiKey, secretKey)

// Order placement
result, err := bitunix.PlaceOrder(exchange.OrderRequest{
    Symbol:    "BTCUSDT",
    Side:      "BUY",
    OrderType: "LIMIT",
    Qty:       "0.001",
    Price:     strPtr("50000"),
    Effect:    "GTC",
    TradeSide: strPtr("OPEN"),
})

// Cancel
err = bitunix.CancelOrder(result.OrderID, "BTCUSDT")

// Market data
price, err := bitunix.GetTickerPrice("BTCUSDT")   // e.g. "70805.3"
minQty, err := bitunix.GetMinOrderQty("BTCUSDT")  // e.g. "0.0001"
```

## Position Reconciliation & Tracking

To track the exact PnL and lifecycle of bot-initiated trades vs manual user trades, the Go backend integrates a unified reconciliation loop:

1. **Order Tagging (`clientId`)**: The `TradeProcessor` injects a `clientId` string formatted as `act_<discordMessageId>_<entryIndex>` into the `OrderRequest`. This identifier is passed to the Exchange.
2. **Order WebSocket**: The `PositionReconciler` subscribes to the Exchange's `Order` WebSocket channels.
3. **Database Linking**: When an order fills, the `PositionReconciler` intercepts the message. If the `clientId` starts with `act_`, it looks up the associated `discord_message_id` from the Postgres `trade_actions` table.
4. **Lifecycle Management**: A new row is inserted into the `position_history` PostgreSQL table when the mapped position `OPEN`s. The Go backend continuously updates the row's `realized_pnl` as ticks arrive, and explicitly updates the status to `CLOSED` when the position disappears from the Exchange snapshot. Manual positions (missing the `act_` tag) are explicitly ignored by the Reconciler, keeping Discord metrics entirely isolated.

## User Exchange Accounts (Encrypted API Key Storage)

In addition to the system-level `.env` keys that power the trade pipeline and position hub, users can store their own exchange API credentials via the PWA. These are encrypted at rest using AES-256-GCM.

### How It Works

1. **Encryption**: The `crypto` package (`go-core/crypto/crypto.go`) provides `Encrypt()` and `Decrypt()` using AES-256-GCM. A 32-byte key is derived from the `ENCRYPTION_KEY` hex string in `.env`.
2. **Storage**: API key and secret key are encrypted before being written to the `call_catch.exchange_accounts` table. The encrypted blobs are base64-encoded (nonce prepended to ciphertext).
3. **Masking**: The GET endpoint decrypts the API key only to extract the last 4 characters for display (e.g. `••••a26`). The secret key is never returned.
4. **Ownership**: Each account is scoped to a `user_id` (from JWT `sub`). Users can only list and delete their own accounts.

### Database Schema

```sql
-- call_catch.exchange_accounts (auto-migrated by GORM)
CREATE TABLE call_catch.exchange_accounts (
    id                   BIGSERIAL PRIMARY KEY,
    user_id              VARCHAR(255) NOT NULL,
    exchange_type        VARCHAR(50) NOT NULL,    -- "bitunix", "phemex"
    label                VARCHAR(100) NOT NULL,   -- user-friendly name
    api_key_encrypted    TEXT,                     -- AES-256-GCM encrypted
    secret_key_encrypted TEXT,                     -- AES-256-GCM encrypted
    is_active            BOOLEAN DEFAULT TRUE,
    created_at           TIMESTAMPTZ,
    updated_at           TIMESTAMPTZ
);
```

### API Endpoints

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/exchange-accounts` | JWT | List user's accounts (keys masked to last 4 chars) |
| POST | `/api/exchange-accounts` | JWT | Add account (encrypts keys before storage) |
| DELETE | `/api/exchange-accounts/:id` | JWT | Delete account (ownership checked) |

**POST body:**
```json
{
  "exchange_type": "bitunix",
  "label": "My Main Account",
  "api_key": "your-api-key-here",
  "secret_key": "your-secret-key-here"
}
```

**GET response (keys masked):**
```json
[
  {
    "id": 1,
    "exchange_type": "bitunix",
    "label": "My Main Account",
    "api_key_masked": "••••a26",
    "is_active": true,
    "created_at": "2026-03-31T13:00:00Z"
  }
]
```

### Supported Exchange Types

The handler validates against an allow-list:
- `bitunix`
- `phemex`

New types require adding to `validExchangeTypes` in `handlers/exchange_accounts.go`.

> **Note:** User exchange accounts are fully wired into the trade pipeline. When a signal is processed, the system automatically looks up all users subscribed to the channel, decrypts their API keys in-memory, and places orders on their mapped exchanges concurrently using lightweight, ephemeral `OrderPlacer` instances.

## Configuration

All configuration is via `go-core/.env`:

```env
# System-level exchange keys (position hub + trade pipeline)
BITUNIX_API_KEY=your-bitunix-api-key
BITUNIX_SECRET_KEY=your-bitunix-secret-key
PHEMEX_API_KEY=your-phemex-api-key
PHEMEX_SECRET_KEY=your-phemex-secret-key

# Encryption key for user exchange accounts (AES-256, 32 bytes hex-encoded)
ENCRYPTION_KEY=your-64-char-hex-string
```

**System-level providers** initialize conditionally — if keys are empty/missing, the provider is skipped with a log message.

**Encryption key** is required for the exchange accounts feature. If missing or invalid, the handler logs a warning and account endpoints will fail.

## Adding a New Exchange Provider

1. Create `go-core/exchange/myexchange.go` implementing `ExchangeProvider`
2. Optionally implement `OrderPlacer` if the exchange supports order placement
3. Add API key fields to `config/config.go` and `.env`
4. Add conditional initialization in `main.go`
5. Add the exchange type string to `validExchangeTypes` in `handlers/exchange_accounts.go`
6. Add the exchange option to `exchangeOptions` in `ExchangeAccountsView.vue`
7. No other frontend changes needed — positions auto-appear in the PWA

## Migration Note

> Exchange order placement was originally implemented in PHP (`PHP/src/Exchange/BitUnixProvider.php`). As of March 2026, it has been fully ported to the Go backend (`go-core/exchange/bitunix.go`). The PHP implementation is retained for reference but is no longer active.
