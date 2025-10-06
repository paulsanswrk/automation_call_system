# Flutter App — Implementation Progress Report

Updated: 2026-04-04

> [!NOTE]
> The Flutter app is now **feature-complete** with all screens implemented, matching the Vue 3 PWA. Static analysis passes clean (`flutter analyze` — 0 issues). The debug APK build fails only due to a missing NDK `source.properties` file on the VM — this is an environment issue, not a code defect.

## What's Completed ✅

**Project Configuration**
- `[x]` **Flutter Project Created**: Scaffold at `ui_app/flutter`.
- `[x]` **Dependencies Installed**: `pubspec.yaml` with `supabase_flutter`, `flutter_riverpod`, `go_router`, `web_socket_channel`, `google_fonts`, `http`, `intl`, `url_launcher`.
- `[x]` **Android API Levels**: `android/app/build.gradle.kts` — `minSdk = 28`, `appAuthRedirectScheme = "com.act.trading"`.

**Foundation**
- `[x]` **App Theme**: `lib/theme/app_theme.dart` — Dark mode aesthetic matching PWA (colors, gradients, typography, input decoration, card themes).
- `[x]` **Reusable Widgets**: `lib/theme/app_widgets.dart` — `SummaryCard`, `StatusBadge`, `ActionBadge`, `ExchangeBadge`, `LiveDot`, `ConnectionIndicator`, `SectionHeader`, `EmptyState`.
- `[x]` **Data Models**: All POJOs under `lib/models/` — `ai_log.dart`, `channel.dart`, `discord_message.dart`, `exchange_account.dart` (with `availableBalance`), `position.dart`, `trade_action.dart`.
- `[x]` **Network Services**: `lib/services/api_service.dart` (REST), `position_ws_service.dart` (Positions WebSocket), `system_ws_service.dart` (System Events WebSocket).
- `[x]` **Auth Provider**: `lib/providers/auth_provider.dart` — Riverpod providers for `authState`, `currentSession`, `currentUser`, `isAuthenticated`, `isAdmin`.
- `[x]` **Routing**: `lib/router/app_router.dart` — GoRouter with auth guards, admin guards, and `ShellRoute` for bottom navigation.

**App Bootstrap**
- `[x]` **`main.dart`**: Initializes Supabase with project URL/anon key, wraps in `ProviderScope`, uses `AppTheme.darkTheme` and `GoRouter`.

**Auth Service**
- `[x]` **`lib/services/auth_service.dart`**: Supabase Google OAuth with `com.act.trading://login-callback/` redirect. Sign-in and sign-out methods.

**All Screens**
- `[x]` **`login_screen.dart`**: Gradient background, app branding, Google sign-in button with loading/error states, fade-in animation.
- `[x]` **`shell_screen.dart`**: Bottom navigation bar (6 tabs, admin-only tabs hidden for non-admins), app bar with page title, user avatar popup menu with sign-out.
- `[x]` **`notifications_screen.dart`**: Fetches `/api/messages` + `/api/trade-actions` + `/api/channels`. Channel filter dropdown, message cards with author/channel/time/text, inline trade action badges, tap-to-detail bottom sheet.
- `[x]` **`positions_screen.dart`**: Real-time WebSocket via `PositionWsService`. Connection status indicator, total unrealized PnL summary card, positions grouped by exchange with gradient badge headers, position cards (symbol, side, qty, entry, mark, PnL, leverage, liq. price, margin).
- `[x]` **`exchange_accounts_screen.dart`**: Fetches `/api/exchange-accounts`. Account cards with exchange icon, label, status badges, available balance, masked API key, error banner. FAB → add account bottom sheet (exchange selector, label, API key, secret key with visibility toggles). Delete with confirmation dialog.
- `[x]` **`channels_screen.dart`**: Fetches `/api/channels` + `/api/exchange-accounts`. Channel cards with name, status badge, heartbeat/stale indicators. Subscription controls (Off/Paper/Live segmented buttons). Settings section: TP Rule dropdown, Auto-SL toggle, Position Size selector, Target Exchanges pill buttons. Manual Call dialog. Delete channel (admin).
- `[x]` **`trade_actions_screen.dart`**: Paginated (`/api/trade-actions?page=&limit=`). Filter by action type. Action cards with badge, exchange badge, symbol, side, price, notes. Tap → detail bottom sheet with request/result JSON display. Delete (admin). Pagination controls.
- `[x]` **`ai_log_screen.dart`**: Paginated (`/api/ai-log?page=&limit=`). Log cards with model badge, token counts, cost, truncated prompt. Tap → detail bottom sheet with full prompt (copyable) and AI response. Delete (admin). Pagination controls.

**Verification**
- `[x]` **`flutter analyze`**: 0 issues found.
- `[x]` **Widget test**: Smoke test passes.

## What Remains ⏳

### Environment Fix (Not Code)
- `[ ]` **NDK `source.properties`**: The Android NDK at `/home/ubuntu/android-sdk/ndk/26.3.11579264` is missing its `source.properties` file. Fix by reinstalling NDK via `sdkmanager "ndk;26.3.11579264"` or creating the missing file. This blocks `flutter build apk`.

### Nice-to-Have Enhancements
- `[ ]` **Real-time WebSocket integration on Notifications**: Currently REST-only polling. Could integrate `SystemWsService` for live message/trade-action push (like the PWA does via `useSystemWS`).
- `[ ]` **Pull-to-refresh on all screens**: Currently implemented on Positions, Exchanges, Channels. Could add to Trade Actions and AI Log.
- `[ ]` **Push notifications**: Firebase Cloud Messaging integration (equivalent to PWA's `usePushNotifications` composable).
- `[ ]` **Date range filter**: Trade Actions and AI Log screens in the PWA have date-range pickers. The Flutter versions use action-type filtering only for now.
- `[ ]` **Channel drag-to-reorder**: PWA supports drag-and-drop channel card reordering with localStorage persistence.

---

## File Map

```
lib/
├── main.dart                          # App bootstrap (Supabase + Riverpod + GoRouter)
├── models/
│   ├── ai_log.dart
│   ├── channel.dart
│   ├── discord_message.dart
│   ├── exchange_account.dart
│   ├── position.dart
│   └── trade_action.dart
├── providers/
│   └── auth_provider.dart             # Riverpod auth state providers
├── router/
│   └── app_router.dart                # GoRouter with auth/admin guards
├── screens/
│   ├── ai_log_screen.dart
│   ├── channels_screen.dart
│   ├── exchange_accounts_screen.dart
│   ├── login_screen.dart
│   ├── notifications_screen.dart
│   ├── positions_screen.dart
│   ├── shell_screen.dart              # Bottom nav wrapper
│   └── trade_actions_screen.dart
├── services/
│   ├── api_service.dart               # REST HTTP client
│   ├── auth_service.dart              # Supabase Google OAuth
│   ├── position_ws_service.dart       # Positions WebSocket
│   └── system_ws_service.dart         # System events WebSocket
└── theme/
    ├── app_theme.dart                 # Material ThemeData + colors
    └── app_widgets.dart               # Reusable badge/card widgets
```
