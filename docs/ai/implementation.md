# AI Integration: Provider Abstraction & Trade Call Analysis

## Overview

The AI subsystem processes Discord trading call messages through an LLM (currently Gemini) to extract structured JSON trade data. It uses a modular provider design so that alternative backends (Claude, OpenAI) can be added with minimal effort.

The AI layer is invoked by the Go `TradeProcessor` whenever a new Discord message arrives. If the AI extracts a valid trade call, a minimum-size order is placed on BitUnix (see `docs/pipeline/implementation.md`).

## Architecture

```
Discord Message (text)
        │
        ▼
┌─────────────────────┐
│  GeminiProvider      │  ◄── Go implementation (ai/gemini.go)
└────────┬────────────┘
         │ returns
         ▼
┌─────────────────────┐
│     AiResponse       │  ◄── struct (Text, Model, TokensIn, TokensOut, RawResponse)
└────────┬────────────┘
         │ logged to
         ▼
┌─────────────────────┐
│  call_catch.ai_log   │  ◄── Supabase/Postgres
└─────────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `go-core/ai/gemini.go` | Gemini API implementation: `Complete()`, `AiResponse`, `ExtractJSON()`, cost calculation |
| `go-core/ai/prompt.go` | `CALL2COMMAND_PROMPT` system prompt constant |
| `go-core/pipeline/trade_processor.go` | Pipeline orchestrator: calls AI → validates → places exchange orders |
| `go-core/models/ai_log.go` | GORM model for `call_catch.ai_log` table |

### Legacy PHP Files (retained for reference)

| File | Purpose |
|------|---------|
| `PHP/src/Ai/AiProviderInterface.php` | Abstract interface: `complete()` + `getName()` |
| `PHP/src/Ai/AiResponse.php` | Value object: text, tokens, model, `extractJson()` helper |
| `PHP/src/Ai/GeminiProvider.php` | Gemini API implementation with token/cost tracking |
| `PHP/src/TradeProcessor.php` | Original pipeline (superseded by Go `pipeline/trade_processor.go`) |

## GeminiProvider (Go)

Uses the `generativelanguage.googleapis.com` REST API (v1beta).

**Configuration:**
- API key: loaded from `.env` → `GEMINI_API_KEY`
- Default model: `gemini-2.5-flash` (overridable via `GEMINI_MODEL`)
- Pricing constants for cost calculation (Gemini 2.0 Flash rates: $0.10/1M input, $0.40/1M output)

**Usage:**
```go
provider := ai.NewGeminiProvider(apiKey, "gemini-2.5-flash")
response, err := provider.Complete(ai.CALL2COMMAND_PROMPT, messageText)

tradeJSON, err := response.ExtractJSON()    // parsed trade data
cost := ai.CalculateCost(response.TokensIn, response.TokensOut)  // USD cost
```

## AiResponse

The `AiResponse` struct provides:

- `Text` — raw LLM text output
- `Model` — model identifier (e.g. `gemini-2.5-flash`)
- `TokensIn` / `TokensOut` — token usage (pointers, nil if unavailable)
- `ExtractJSON()` — parses JSON from the response, handling ` ```json ``` ` code fences and bare JSON objects. Returns `(map[string]interface{}, error)`.
- `ai.CalculateCost()` — static function that computes USD cost from token counts

## Database: `call_catch.ai_log`

| Column | Type | Description |
|--------|------|-------------|
| `id` | serial | Primary key |
| `created_at` | timestamptz | Auto-set on insert |
| `model` | text | e.g. `gemini-2.5-flash` |
| `system_prompt` | text | System prompt text |
| `user_prompt` | text | User message text |
| `response` | text | Clean JSON (unwrapped from markdown fences) |
| `context` | text | Source context (e.g. `trade_pipeline: discord_msg_123`) |
| `tokens_in` | integer | Prompt tokens |
| `tokens_out` | integer | Completion tokens |
| `cost_usd` | numeric(12,8) | Calculated cost in USD |
| `is_test` | boolean | Whether this was a test invocation |

## Configuration

```env
GEMINI_API_KEY=your-gemini-api-key
GEMINI_MODEL=gemini-2.5-flash
```

Both are loaded from `go-core/.env` via `config.Load()`.

## Adding a New AI Provider

1. Create a new struct implementing `Complete(systemPrompt, userMessage string) (*AiResponse, error)`
2. Map the provider's response format to `AiResponse` (Text, TokensIn, TokensOut, Model)
3. Add a cost calculation function with the provider's pricing
4. Swap the provider in `main.go` or make it configurable via `.env`

## Migration Note

> This AI integration was originally implemented in PHP (`PHP/src/Ai/GeminiProvider.php`). As of March 2026, it has been fully ported to the Go backend (`go-core/ai/gemini.go`). The PHP implementation is retained for reference but is no longer active.
