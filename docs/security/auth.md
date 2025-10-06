# Authentication & Role Management

## Overview

We use **Supabase Auth** (Google OAuth) to authenticate users in the PWA. Authentication creates a JWT (JSON Web Token), which the Go backend strictly verifies on all sensitive API routes.

Instead of hitting the database repeatedly to check a user's role/permissions, we store their Role payload directly inside the signed JWT.

## Admin Role (`app_metadata`)

Supabase provides two JSONB columns on the `auth.users` system table:
- `user_metadata`: Public data the user can update (e.g., name, avatar, timezone).
- `app_metadata`: **System-only** data that cannot be altered by users via the client SDK. This is exactly where we store roles like `"admin"`.

Because it is system-level data, Supabase automatically embeds it into the user's JWT when they log in.

### 1. Structure

An admin user's token contains claims like this:
```json
{
  "sub": "b2c1f-4bbf-9da2-0...",
  "aud": "authenticated",
  "app_metadata": {
    "provider": "google",
    "role": "admin"
  },
  "user_metadata": {
    "full_name": "Paul..."
  }
}
```

### 2. Guarding APIs (Go Backend)

In the Go backend middleware (`go-core/middleware/auth.go`), we decode the JWT token using the `Supabase JWKS`. You can simply extract the `app_metadata` to guard sensitive routes without making a single database query!

Example concept:
```go
appMeta, ok := claims["app_metadata"].(map[string]interface{})
if ok && appMeta["role"] == "admin" {
    // User is an admin
} else {
    // Return 403 Forbidden
}
```

### 3. Granting Admin Access

Since users cannot change their own `app_metadata`, you must update the database directly using SQL (or via a secure backend API that uses a Supabase Service Role key).

**Direct SQL Method:**
```sql
UPDATE auth.users 
SET raw_app_meta_data = raw_app_meta_data || '{"role": "admin"}'::jsonb 
WHERE email = 'your.email@gmail.com';
```

*(Note: The `||` operator merges the JSON objects cleanly without destroying existing `provider` metadata).*

Once you run this query, force log out and log back into the PWA so Supabase issues a fresh JWT token containing the new `"role": "admin"` claim.
