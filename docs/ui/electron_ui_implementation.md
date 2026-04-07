# ACT Trading - Electron Desktop UI Implementation

This document outlines the architecture and key implementation details of the ACT Trading Electron desktop application, located at `ui_app/electron/`. 

The desktop app ports the 7 PWA views into a native environment, leveraging Electron-specific features.

## Architecture Overview

The application is structured into two main processes, bridging the Node.js backend environment (Main Process) with the Vue 3 frontend (Renderer Process). 

```text
ui_app/electron/
├── src/
│   ├── main/           # Electron main process
│   │   ├── index.ts    # Window mapping, tray, IPC handlers, OAuth, single-instance lock
│   │   └── preload.ts  # contextBridge API exposing safe methods to renderer
│   └── renderer/       # Vue 3 SPA (Single Page Application)
│       ├── composables/ # State management (useAuth, useSystemWS, useSettings)
│       ├── layouts/     # DashboardLayout shell
│       ├── lib/         # API wrappers, Supabase client, Electron IPC helpers
│       ├── styles/      # Custom CSS variables, global styles, layout, components
│       └── views/       # 7 core views
├── resources/icon.png  # App icon asset
├── package.json        # Dependencies (Vue 3, Vue Router, Supabase JS, Electron, Vite)
├── vite.config.ts      # Multi-target build configuration
├── electron-builder.yml# Platform targets configuration (Linux/macOS/Windows)
└── tsconfig*.json      # TypeScript configurations
```

## Key Architectural Decisions

1. **Custom Styling Over UI Frameworks:** The desktop app eliminates the PrimeVue dependency used in the PWA. Everything is styled with custom CSS to achieve a leaner build footprint (~240KB savings) and native look, using standard elements like `<input type="date">` and emoji icons.
2. **In-App OAuth:** Instead of redirecting to a system browser for Google OAuth logins, the app spawns an in-app `BrowserWindow`. This window captures the redirect URL to silently extract the session tokens, keeping the authentication flow entirely contained.
3. **Hash Routing:** The Vue Router operates in hash mode to ensure compatibility with Electron's `file://` protocol when running the packaged application.
4. **Vite Build System:** Vite seamlessly handles multi-entry building for `main`, `preload`, and `renderer` code seamlessly. 

## Desktop-Specific Features

The Electron app enhances the core PWA experience with native OS integrations:

*   **Native OS Notifications:** Critical trading signals are passed via IPC to the main process and pushed to the operating system's native notification center.
*   **System Tray Integration:** A system tray icon allows minimizing the app to the background and displays a badge count of unread signals. On macOS, this extends to an unread count badge on the Dock icon.
*   **Single Instance Lock:** Prevents users from accidentally opening duplicate instances of the trading platform.
*   **Desktop Layout Tuning:** Implements a collapsible sidebar, drag-regions for frameless window movement, and ensures the responsive design caters primarily to desktop dimensions.

## View Structure

The renderer process implements 7 core views, communicating with the Go backend API (`/api/*`):

| View | Purpose |
|------|---------|
| `/login` (`LoginPage.vue`) | Entry point handling the Google OAuth trigger. |
| `/` (`NotificationFeed.vue`) | Real-time message feed via WebSockets, file upload capabilities, and manual entries. |
| `/positions` (`PositionsView.vue`) | Real-time PnL and active trades feed via `/api/positions/ws`. |
| `/exchange-accounts` (`ExchangeAccountsView.vue`) | CRUD for API keys connecting BitUnix or Phemex. |
| `/channels` (`ChannelsView.vue`) | Admin view for configuring telegram channel listeners, mapping position sizes, and toggling strategy automation. |
| `/trade-actions` (`TradeActionsView.vue`) | Admin ledger of system actions (orders placed, skipped, errors) for debugging signals. |
| `/ai-log` (`AILogView.vue`) | Admin oversight of AI parsing operations, displaying input prompts, token usage, and costs. |

## IPC Communication Details (Preload Bridge)

The `preload.ts` script securely exposes the following APIs to the Vue 3 application:

*   `electronAPI.oauthLogin()` → Invokes the main process login window popup.
*   `electronAPI.getVersion()` → Retrieves running app version.
*   `electronAPI.setTrayBadge(count)` → Updates unread notification counters.
*   `electronAPI.showNotification(title, body)` → Dispatches native system toasts.
*   `electronAPI.onDeepLink(callback)` → Registers a handler for OS deep link schemas (`act-trading://`).

## Storage & Configuration

*   **Preferences:** `electron-store` manages persistent settings such as window geometry, API base URLs, and local user startup preferences.
*   **Global Variables:** Controlled by an `.env` file containing Supabase keys.

## Build Scripts

From the `ui_app/electron` directory:
*   `npm install` - Installs dependencies.
*   `npm run dev` - Starts Vite dev server with Electron running.
*   `npm run build` - Initiates Vite production build and `electron-builder` packaging.
