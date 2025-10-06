# Authentication

## Overview

All user-facing access is authenticated via **Supabase Auth (Google OAuth)**. The system uses JWTs throughout — Supabase issues them, the PWA stores and forwards them, and the Go backend verifies them using public keys.

```
┌──────────────┐  1. OAuth   ┌──────────────┐  2. JWT   ┌──────────────┐
│   Google     │◄───────────►│  Supabase    │──────────►│   PWA        │
│   OAuth      │             │  Auth        │           │  (Vue 3)     │
└──────────────┘             └──────────────┘           └──────┬───────┘
                                    │                          │
                              3. JWKS public keys        4. Bearer token
                                    │                          │
                              ┌─────▼──────┐            ┌──────▼───────┐
                              │  /.well-   │◄───────────│  Go API      │
                              │  known/    │  (startup)  │  (Gin)       │
                              │  jwks.json │             └──────────────┘
                              └────────────┘
```

1. User clicks "Sign in with Google" → Supabase Auth handles the OAuth flow
2. Supabase issues a JWT (access token) to the PWA
3. Go backend fetches public signing keys from Supabase's JWKS endpoint at startup
4. PWA attaches the JWT as `Authorization: Bearer <token>` on every API request

---

## Components

### PWA (Supabase Auth Client)

**Sign-in** — `src/composables/useAuth.ts`:
```typescript
supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.origin } })
```

**Route guard** — `src/router.ts`:
- `beforeEach` hook calls `supabase.auth.getSession()`
- No session → redirect to `/login`
- Has session + on `/login` → redirect to `/`

**Authenticated fetch** — `src/lib/api.ts`:
```typescript
export async function apiFetch(path: string, init?: RequestInit): Promise<Response> {
  const { data: { session } } = await supabase.auth.getSession()
  return fetch(`${API_BASE}${path}`, {
    ...init,
    headers: { ...init?.headers, Authorization: `Bearer ${session?.access_token ?? ''}` },
  })
}
```

All API calls in the PWA use `apiFetch()` which automatically attaches the JWT.

### Go Backend (JWT Verification via JWKS)

**Middleware** — `middleware/auth.go`:

At startup, the Go backend fetches public signing keys from:
```
GET https://thpkiasoiifmapkoerls.supabase.co/auth/v1/.well-known/jwks.json
```

This returns the public key(s) used by Supabase to sign JWTs. The middleware then:
1. Extracts `Authorization: Bearer <token>` from the request header
2. Parses the JWT and verifies its signature against the JWKS public keys
3. Checks the `exp` (expiry) claim
4. On success: stores `claims` and `userID` in the Gin context, calls `Next()`
5. On failure: returns `401 {"error": "..."}`

**Libraries**: `golang-jwt/jwt/v5` (JWT parsing) + `MicahParks/keyfunc/v3` (JWKS fetching & caching).

**No shared secret needed** — verification uses public keys only. Keys are cached in memory and auto-refreshed in the background by `keyfunc`.

**Route protection**:

| Endpoint | Auth | Middleware |
|----------|------|------------|
| `/api/health` | Public | None |
| `/api/messages` | JWT required | `JWTAuth(jwks)` |
| `/api/trade-actions` | JWT required | `JWTAuth(jwks)` |
| `/api/ai-log` | JWT required | `JWTAuth(jwks)` |

### Supabase Realtime (WebSocket)

The `@supabase/supabase-js` client automatically attaches the user's JWT to the WebSocket connection. Combined with RLS policies (`authenticated` role can `SELECT`), this ensures only signed-in users receive live events.

### Supabase RLS (Database Level)

All tables in `call_catch` schema have Row Level Security enabled:

| Table | Policy | Role |
|-------|--------|------|
| `discord_messages` | `SELECT` | `authenticated` |
| `ai_log` | `SELECT` | `authenticated` |
| `trade_actions` | `SELECT` | `authenticated` |
| `trade_actions` | `ALL` | `service_role` |

Writes from the PHP handler use the database password (bypasses RLS via direct Postgres connection, `service_role` equivalent).

---

## Token Lifecycle

| Property | Value |
|----------|-------|
| **Issuer** | Supabase Auth (`thpkiasoiifmapkoerls`) |
| **Algorithm** | ES256 (Elliptic Curve, asymmetric) |
| **Access token expiry** | 1 hour (Supabase default) |
| **Refresh** | Handled automatically by `supabase-js` — refreshes before expiry |
| **Key rotation** | Supported via Supabase [JWT Signing Keys](https://supabase.com/docs/guides/auth/signing-keys) — Go backend auto-picks up new keys from JWKS |

---

## Configuration

### PWA (`ui_app/pwa/.env`)
```
VITE_SUPABASE_URL=https://thpkiasoiifmapkoerls.supabase.co
VITE_SUPABASE_ANON_KEY=<anon key>
```

### Go Backend (`go-core/.env`)
```
SUPABASE_URL=https://thpkiasoiifmapkoerls.supabase.co
```

### Google OAuth (external)
- **GCP Console**: OAuth 2.0 Client ID (Web application)
  - Authorized JavaScript origin: `https://act2026.mooo.com`
  - Authorized redirect URI: `https://thpkiasoiifmapkoerls.supabase.co/auth/v1/callback`
- **Supabase Dashboard**: [Auth → Providers → Google](https://supabase.com/dashboard/project/thpkiasoiifmapkoerls/auth/providers) — Client ID + Secret configured

---

## Key Files

| File | Purpose |
|------|---------|
| `ui_app/pwa/src/composables/useAuth.ts` | Reactive auth state, sign-in/sign-out |
| `ui_app/pwa/src/lib/api.ts` | Authenticated fetch helper |
| `ui_app/pwa/src/lib/supabase.ts` | Supabase client (Auth + Realtime) |
| `ui_app/pwa/src/router.ts` | Route guard (session check) |
| `go-core/middleware/auth.go` | JWKS-based JWT verification middleware |
| `go-core/main.go` | JWKS init + route group with auth middleware |
