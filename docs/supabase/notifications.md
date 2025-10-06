# Web Push Notifications

## Overview

Push notifications are sent to all subscribed devices when a new `trade_actions` row is inserted. Works on iOS (Home Screen PWA), Android, and desktop browsers — including when the app is closed or the device is locked.

## Architecture

```
trade_actions INSERT
  → PostgreSQL trigger (pg_net)
  → Supabase Edge Function (notify-push)
    → Reads push_subscriptions via public view
    → Encrypts payload per RFC 8291
    → Signs with VAPID (ES256)
    → POSTs to Apple APNs / Google FCM
    → Device shows notification
```

## Components

### Database

| Object | Schema | Purpose |
|--------|--------|---------|
| `push_subscriptions` table | `call_catch` | Stores per-device push endpoints + encryption keys |
| `push_subscriptions_view` | `public` | View for Edge Function access (avoids schema exposure) |
| `notify_push_on_trade_action()` | `call_catch` | Trigger function — calls Edge Function via `pg_net` |
| `trade_action_push_notify` trigger | `call_catch` | AFTER INSERT on `trade_actions` |

### Edge Function: `notify-push`

- **Trigger**: Database webhook via `pg_net` (or direct HTTP POST)
- **JWT verification**: Disabled (called from DB trigger, not user-facing)
- **Secrets** (set in Supabase Dashboard → Edge Functions → Secrets):

| Secret | Description |
|--------|-------------|
| `VAPID_PUBLIC_KEY` | ECDSA P-256 public key (URL-safe base64) |
| `VAPID_PRIVATE_KEY` | ECDSA P-256 private key (URL-safe base64) |
| `VAPID_SUBJECT` | Contact URI, e.g. `mailto:admin@act2026.mooo.com` |

### Go Backend

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/push/subscribe` | POST | Save push subscription (upsert by endpoint) |
| `/api/push/subscribe` | DELETE | Remove push subscription |

Both require JWT authentication (same as other `/api/` routes).

### PWA Client

| File | Purpose |
|------|---------|
| `src/sw.ts` | Custom service worker — `push` + `notificationclick` handlers |
| `src/composables/usePushNotifications.ts` | Subscribe/unsubscribe logic + permission handling |
| `src/layouts/DashboardLayout.vue` | "Enable Notifications" toggle button in sidebar |

## iOS Requirements

1. User must open `https://act2026.mooo.com` in **Safari**
2. Tap **Share → Add to Home Screen**
3. Open from the Home Screen icon (standalone mode)
4. Tap **"Enable Notifications"** inside the app
5. Accept the iOS permission prompt

Push does **not** work from a regular Safari tab — only from a Home Screen PWA (iOS 16.4+).

## Testing

Send a test notification via curl:

```bash
curl -X POST https://thpkiasoiifmapkoerls.supabase.co/functions/v1/notify-push \
  -H "Content-Type: application/json" \
  -d '{"record": {"action": "TEST", "symbol": "BTCUSDT", "side": "LONG"}}'
```

Expected response: `{"sent":1,"total":1}`

Full pipeline test (triggers the DB webhook):

```sql
INSERT INTO call_catch.trade_actions (discord_message_id, action, symbol, side, notes)
VALUES ('test-push-' || gen_random_uuid(), 'TEST', 'BTCUSDT', 'LONG', 'Push test');
```

## VAPID Keys

Generated once. **Do not rotate** — changing keys invalidates all existing subscriptions.

- Public key is stored in `ui_app/pwa/.env` as `VITE_VAPID_PUBLIC_KEY`
- Both keys are stored as Supabase Edge Function secrets
- Keys use ECDSA P-256 curve, URL-safe base64 encoding

## Notification Payload Format

The Edge Function sends this JSON to the service worker:

```json
{
  "title": "ACT: PLACE_ORDER",
  "body": "BTCUSDT LONG",
  "url": "/"
}
```

The service worker displays it as an OS notification with the ACT icon.

## Expired Subscription Cleanup

When APNs or FCM returns 410 (Gone) or 404, the Edge Function automatically deletes the expired subscription from the database.
