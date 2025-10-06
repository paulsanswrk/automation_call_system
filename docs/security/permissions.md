# Security & Permissions

## Overview

The PWA relies on Google OAuth via **Supabase Auth**. This provides us with a cryptographically signed JSON Web Token (JWT) that our Go backend automatically intercepts and validates against Supabase's JWKS public keys. 

To structure roles (like `admin`), we take advantage of Supabase's native token augmentation using the system-secured `app_metadata` field, meaning we never have to query the database to know what permissions an active user has.

---

## The Admin Role (`app_metadata`)

Supabase provides two metadata fields on its `auth.users` system table:
- `user_metadata`: Public data a user can manually update (e.g., timezone, avatar_url).
- `app_metadata`: **System-secured** metadata securely injected directly into the user's active JWT when they log in.

If a user is assigned an admin role, their JWT payload cleanly unpacks like this:
```json
{
  "sub": "b2c1f-4bb2-ad...",
  "aud": "authenticated",
  "app_metadata": {
    "provider": "google",
    "role": "admin"
  }
}
```

### Granting the Admin Role

Users cannot give themselves administrative privileges. Since `app_metadata` is physically locked, you must query your Supabase PostgreSQL pooler directly using raw SQL or use a secure Superadmin API key.

**Direct SQL Method:**
```sql
UPDATE auth.users 
SET raw_app_meta_data = raw_app_meta_data || '{"role": "admin"}'::jsonb 
WHERE email = 'your.email@example.com';
```

> [!IMPORTANT]  
> The `||` JSONB operator merges the new role without overwriting the critical underlying `provider` objects already embedded within `raw_app_meta_data`.

*(Note: The user will need to log out and log back into the PWA so Supabase generates a brand new token containing the updated claim).*

---

## 1. Frontend Restrictions (PWA UI)

By simply injecting the `useAuth()` reactive hook directly into components, we can parse the properties out of the active user session synchronously to lock down the interface.

**Navigation Trimming (`DashboardLayout.vue`)**:
```typescript
const { user } = useAuth()
// Automatically calculates "true" if the role is 'admin'
const isAdmin = computed(() => (user.value?.app_metadata as any)?.role === 'admin')
```
```html
<router-link to="/ai-log" v-if="isAdmin">AI Log</router-link>
```

**Guard Rails (`router.ts`)**:
To protect against users manually guessing or typing restricted URLs into the address bar, the Vue Router acts as a unified gatekeeper.
```typescript
  // router.ts global route definition
  {
    path: 'ai-log',
    meta: { requiresAdmin: true }
  }
```

If the router detects a `requiresAdmin: true` metadata tag during its `beforeEach` invocation, it physically intercepts the page load, checks their active JWT claim, and aggressively reroutes unauthorized standard users back to the safe `/positions` dashboard.

---

## 2. Backend Restrictions (Go Core API)

While the frontend shields UI workflows, the actual backend API strictly prevents unauthorized database pulling/dumping.

We leverage an exact `middleware.AdminOnly()` Gin handler in `go-core/middleware/auth.go`. Because it runs *after* the initial `middleware.JWTAuth(jwks)` block parses the OAuth token, it directly unpacks the dictionary to assert the role:

```go
appMetaRaw, hasMeta := claims["app_metadata"]
appMeta, ok := appMetaRaw.(map[string]interface{})

if !ok || appMeta["role"] != "admin" {
    c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "admin access required"})
    return
}
```

**Route Groups (`main.go`)**:

The API has three permission tiers:

### Public Routes (no auth)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check |
| `/api/discord/message` | POST | Discord message ingestion |
| `/ws/discord` | GET | WebSocket for Discord injector |

### JWT-Protected Routes (any authenticated user)

```go
api := r.Group("/api")
api.Use(middleware.JWTAuth(jwks))
{
    api.GET("/messages", h.GetMessages)
    api.POST("/push/subscribe", h.SavePushSubscription)
    api.DELETE("/push/subscribe", h.DeletePushSubscription)
    api.GET("/positions", posHandler.GetPositions)
    api.GET("/positions/ws", posHandler.HandleWebSocket)
    api.GET("/channels", channelHandler.GetChannels)
    api.POST("/channels", channelHandler.CreateChannel)
    api.POST("/channels/:id/subscribe", channelHandler.Subscribe)
    api.DELETE("/channels/:id/subscribe", channelHandler.Unsubscribe)
    api.GET("/exchange-accounts", exchangeAccountHandler.GetAccounts)
    api.POST("/exchange-accounts", exchangeAccountHandler.CreateAccount)
    api.DELETE("/exchange-accounts/:id", exchangeAccountHandler.DeleteAccount)
}
```

### Admin-Only Routes (JWT + `app_metadata.role == "admin"`)

```go
adminRoutes := api.Group("/")
adminRoutes.Use(middleware.AdminOnly())
{
    adminRoutes.GET("/trade-actions", h.GetTradeActions)
    adminRoutes.DELETE("/trade-actions/:id", h.DeleteTradeAction)
    adminRoutes.GET("/ai-log", h.GetAILog)
    adminRoutes.DELETE("/ai-log/:id", h.DeleteAILog)
    adminRoutes.DELETE("/channels/:id", channelHandler.DeleteChannel)
}
```

---

## 3. Per-User Data Ownership (Exchange Accounts)

Exchange account management (`/api/exchange-accounts`) uses a **per-user ownership** model rather than a role-based gate. Any authenticated user can manage their own exchange accounts, but they cannot see or delete another user's accounts.

The handler extracts the `userID` from the JWT `sub` claim (set by `middleware.JWTAuth`) and scopes all database queries:

```go
userID, _ := c.Get("userID")
// GET: WHERE user_id = ?
// DELETE: WHERE id = ? AND user_id = ?
```

This means:
- **No admin role required** to add/view/delete your own exchange accounts
- **Ownership enforced server-side** — a user cannot guess another user's account ID and delete it
- API keys are **AES-256-GCM encrypted** before storage and **never returned in plaintext** — only the last 4 characters are shown (e.g. `••••a26`)

See `docs/exchange/implementation.md` for full details on the encryption scheme.

---

## 4. Encryption at Rest (API Keys)

User-provided exchange API keys are encrypted using **AES-256-GCM** before being written to PostgreSQL. The encryption key is a 32-byte value stored as a 64-character hex string in the `ENCRYPTION_KEY` environment variable.

| Layer | What's Stored | Format |
|-------|---------------|--------|
| Database | Encrypted ciphertext | Base64(nonce + GCM ciphertext) |
| API response | Masked key | `••••` + last 4 chars |
| Server memory | Plaintext (transient, during encrypt/decrypt only) | Raw string |

The encryption key itself never leaves the server environment. If the key is rotated, existing encrypted values become undecryptable — re-encryption migration would be needed.

