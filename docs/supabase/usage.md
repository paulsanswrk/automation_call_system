# Supabase — How We Use It

## Project

| Property | Value |
|----------|-------|
| Project ref | `thpkiasoiifmapkoerls` |
| Region | `eu-north-1` |
| Dashboard | [supabase.com/dashboard/project/thpkiasoiifmapkoerls](https://supabase.com/dashboard/project/thpkiasoiifmapkoerls) |
| API URL | `https://thpkiasoiifmapkoerls.supabase.co` |
| DB pooler | `aws-1-eu-north-1.pooler.supabase.com:6543` (transaction mode) |

---

## Features Used

### 1. PostgreSQL Database

All application data lives in the **`call_catch`** schema (not `public`).

#### Tables

| Table | Purpose | Writes from | Reads from |
|-------|---------|-------------|------------|
| `discord_messages` | Captured Discord trade calls | PHP handler (Doctrine ORM) | Go API (GORM) |
| `ai_log` | Gemini AI analysis results (prompts, responses, tokens, cost) | PHP handler | Go API |
| `trade_actions` | Exchange orders placed (action, symbol, side, price, qty, SL/TP) | PHP handler | Go API |

#### Connection Patterns

| Component | Connection method | Port |
|-----------|------------------|------|
| **PHP handler** | Doctrine DBAL via Supavisor transaction pooler | 6543 |
| **Go API (Gin)** | GORM + pgx (`PreferSimpleProtocol: true`) via Supavisor transaction pooler | 6543 |
| **PWA (Realtime only)** | `@supabase/supabase-js` WebSocket | 443 |

> **Important**: The transaction-mode pooler (port 6543) does **not** support prepared statements. Both PHP (Doctrine) and Go (GORM/pgx) must disable them. In Go this is done via `PreferSimpleProtocol: true`.

### 2. Authentication (Supabase Auth)

- **Provider**: Google OAuth only
- **Flow**: PWA calls `supabase.auth.signInWithOAuth({ provider: 'google' })` → Supabase redirects to Google → callback → JWT session
- **Guard**: Vue Router `beforeEach` checks `supabase.auth.getSession()`
- **API auth**: PWA attaches the Supabase JWT as `Authorization: Bearer <token>` on all Go API requests via `apiFetch()` helper (`src/lib/api.ts`)
- **Go verification**: Gin middleware verifies JWTs using **JWKS public key discovery** from `/.well-known/jwks.json` — no shared secret needed, supports key rotation
- **Config**: Google Cloud Console OAuth credentials configured in [Supabase Auth → Providers → Google](https://supabase.com/dashboard/project/thpkiasoiifmapkoerls/auth/providers)

See [auth.md](auth.md) for full details.

### 3. Realtime (WebSocket)

The PWA subscribes to **live INSERT events** on two tables for instant updates on the Notifications page:

```typescript
supabase.channel('discord-messages-realtime')
  .on('postgres_changes', { event: 'INSERT', schema: 'call_catch', table: 'discord_messages' }, ...)
  .on('postgres_changes', { event: 'INSERT', schema: 'call_catch', table: 'trade_actions' }, ...)
  .subscribe()
```

This is the **only direct Supabase connection** from the PWA — all REST reads go through the Go backend.

### 4. Row Level Security (RLS)

All three tables have RLS enabled:

| Table | Policy | Role | Permission |
|-------|--------|------|------------|
| `discord_messages` | Authenticated users can read | `authenticated` | `SELECT` |
| `ai_log` | Authenticated users can read | `authenticated` | `SELECT` |
| `trade_actions` | Authenticated users can read | `authenticated` | `SELECT` |
| `trade_actions` | service_role_all | `service_role` | `ALL` |

Writes are done by the PHP handler using the **database password** (bypasses RLS via direct Postgres connection).

---

## Architecture

```
┌──────────────┐  Bearer JWT  ┌───────────┐  JWKS   ┌─────────────────────┐
│  PWA (Vue 3) │────REST─────▶│  Go API   │◄───────▶│  Supabase Auth      │
│              │              │  (Gin)    │──SQL──▶ │  Supabase Postgres  │
│              │──WSS──────────────────────────────▶│  (Realtime)         │
│              │──OAuth────────────────────────────▶│  (Auth)             │
└──────────────┘              └───────────┘         └─────────────────────┘
                                                             ▲
┌──────────────┐                                             │
│ PHP Handler  │──────────SQL (Doctrine)─────────────────────┘
│ (server.php) │
└──────────────┘
```

- **REST reads** → PWA sends JWT → Go backend (Gin + JWKS auth middleware) → GORM → Supabase Postgres
- **Realtime** → PWA ↔ Supabase WebSocket (JWT auto-attached, RLS enforced)
- **Auth** → PWA ↔ Supabase Auth (Google OAuth → JWT)
- **JWKS** → Go backend fetches public signing keys from Supabase at startup (auto-refreshed)
- **Writes** → PHP handler (Doctrine) → Supabase Postgres (bypasses RLS via DB password)

---

## Migrations

Applied via Supabase Dashboard / MCP:

| Version | Name |
|---------|------|
| `20260306131421` | `create_discord_messages_table` |
| `20260306175157` | `add_server_name_column` |
| `20260306175355` | `drop_server_name_column` |
| `20260311070629` | `create_call_catch_schema_and_ai_log` |
| `20260311070633` | `move_discord_messages_to_call_catch` |
| `20260311181821` | `create_trade_actions_table` |
| `20260316070007` | `add_tp_sl_entry_index_to_trade_actions` |
| `20260316084807` | `add_request_to_trade_actions` |
| `20260316164720` | `add_rls_select_policies` |

---

## Credentials

| Secret | Location | Used by |
|--------|----------|---------|
| Supabase URL | `go-core/.env` → `SUPABASE_URL` | Go API (JWKS endpoint) |
| Anon key (JWT) | `ui_app/pwa/.env` → `VITE_SUPABASE_ANON_KEY` | PWA (Auth + Realtime) |
| DB password | `PHP/settings.ini` → `SUPABASE_DB_PASSWORD` | PHP handler |
| DB password | `go-core/.env` → `DB_PASSWORD` | Go API |

All credential files are gitignored. See `.env.example` files for templates.

> **Note**: The Go backend does **not** need a JWT secret. It verifies tokens using public keys fetched from the Supabase JWKS endpoint.
