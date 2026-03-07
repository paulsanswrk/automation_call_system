# Automation Call System

**Automation Call System** is a high-performance, multi-exchange crypto trading pipeline. It automatically ingests trading signals from channels (Discord, Telegram, Text files), processes the natural language through Google's Gemini AI to extract structured trade parameters (Pair, Direction, Entries, Take Profits, Stop Loss), and routes them to user-mapped API keys on supported exchanges (BitUnix, Phemex).

## Features

- **Multi-Source Ingestion:** Webhooks and WebSockets for Discord and Telegram, plus manual text file bulk parsing.
- **AI-Powered Extraction:** Uses Gemini 2.5 Flash to rapidly convert unstructured human trading signals into structured JSON.
- **Dynamic Risk Management:** User-configured mappings allow dynamic positioning (`min_qty`, `tp_wise_min_qty`, `usd_amount`) and automatic stop losses.
- **Multi-Exchange Execution:** Direct integrations with BitUnix and Phemex via REST and WebSocket.
- **Real-Time Position Tracking:** WebSocket aggregators sync live PnL and position states directly to the UI.
- **Cross-Platform Interfaces:** Includes a responsive Vue.js PWA for web users and a comprehensive Flutter mobile app.

## Architecture

1. **Ingestion Layer:** Captures webhook pushes from channels. Identifies whether it's an actionable signal.
2. **AI Processing Layer (Go Pipeline):** A central orchestrator (`go-core/pipeline/trade_processor.go`) runs natural language signals through Gemini, logging all inputs/outputs for auditing.
3. **Execution Layer:** Fans out validated trades to ephemeral, per-user `OrderPlacer` instances. 
4. **Data Layer (Supabase):** PostgreSQL with GORM provides the source of truth for message deduplication, user exchange encrypted credentials, trade logs, and active position history. Supabase Realtime acts as a pub/sub backbone for the PWA.

## Tech Stack

- **Backend:** Go 1.21+ (Gin, GORM, gorilla/websocket)
- **Database:** Supabase PostgreSQL (utilizing the Supavisor connection pooler)
- **Web Frontend:** Vue 3 (Vite, TypeScript, PWA)
- **Mobile Frontend:** Flutter
- **AI Provider:** Google Gemini API
- **Scraping / Injectors:** Puppeteer / Browser Automation JS

## Repository Structure

```text
automation_call_system/
├── go-core/                 # Main Go backend server (REST APIs, Pipeline, WS hubs)
├── ui_app/
│   ├── pwa/                 # Vue 3 Progressive Web App dashboard
│   └── flutter/             # Native mobile apps (Android/iOS)
├── browser_automation/      # Scripts for headless Chrome data capture (Discord Injectors)
├── docs/                    # Extensive technical documentation and architecture diagrams
└── start_insecure_chrome.sh # Shell utility to start debugging browser sessions
```

## Getting Started

### Prerequisites
- Go 1.21+
- Node.js 18+ (for PWA)
- Flutter SDK (for mobile)
- Supabase Project

### 1. Database Setup
Ensure your Supabase PostgreSQL instance is running. The initial schemas reside in the `call_catch` namespace. 

### 2. Configure Environment
In the `go-core/` directory, create a `.env` file from the example:
```env
DB_HOST=aws-1-eu-north-1.pooler.supabase.com
DB_PORT=6543
DB_NAME=postgres
DB_USER=postgres.[project_ref]
DB_PASSWORD=[password]
DB_SEARCH_PATH=call_catch
SERVER_PORT=8080
GEMINI_API_KEY=your_gemini_key
ENCRYPTION_KEY=64-char-hex-string
TRADE_PIPELINE_ENABLED=true
```

### 3. Run the Go Backend
```bash
cd go-core
go build -o go-core-server .
./go-core-server
```
*The server exposes the REST API on `localhost:8080`.*

### 4. Run the PWA
```bash
cd ui_app/pwa
npm install
npm run dev
```

### 5. Start Data Injectors (Optional)
If running Discord scrapers, utilize the `/browser_automation` tooling and ensure the Chrome extensions are loading successfully by running `./start_insecure_chrome.sh`.

## Security Notes
- The `ENCRYPTION_KEY` in your `.env` is essential for interacting securely with the database. It symmetrically decrypts strings inside `exchange_accounts`. If lost, those exchange API keys cannot be recovered.
- The `TRADE_PIPELINE_ENABLED` flag toggles "Dry Run" mode. Set to `false` heavily for local UI testing.

## Documentation
Please check the `/docs` directory for detailed UML workflows, sequence diagrams, and deep dives into the execution constraints for specific exchanges.
