To manually test the entire end-to-end flow of the reconciliation system, follow these steps:

### 1. Trigger a Bot Trade

Send a test message via the Discord injector (or use the Capture Control modal's "Send Selected to Handler" button). Ensure the call is for a real coin and structured so the AI recognizes it as a trade call.

The Go backend will:
1. Persist the message to `discord_messages`
2. Run Gemini AI analysis asynchronously
3. Place orders on BitUnix if the AI extracts valid trade data

*   **What to look for**: Check your `call_catch.trade_actions` database table. You should see new rows with dynamically generated `client_id` values (e.g., `act_123456789_0`). Check the Go server logs for pipeline output:
    ```bash
    journalctl -u go-core -f
    ```
    You should see:
    ```
    [Discord→Pipeline] message_id=123456789 action=PLACE_ORDER notes=Entry #0: Order placed (TP=..., SL=...)
    ```

### 2. Wait for the Order to Fill

The exchange will receive your limit/market order. For the Go Reconciler to officially map the position, the order must actually fill to become an **open position**.

*   **What to look for**: In the Go backend logs, the exact second the exchange fills the order, you will see:
    ```
    [reconciler] Mapped bitunix BTCUSDT -> DiscordCall: 123456789
    [reconciler] Inserted OPEN position_history ID 1 for bitunix:pos100
    ```

### 3. Verify the Active Map

*   **Database**: Check the `call_catch.position_history` table. There should be a new row with `status = 'OPEN'`.
*   **Frontend**: Open your PWA dashboard at `https://act2026.mooo.com/positions`. The position will be ticking normally. If you inspect the raw WebSocket frames in your browser's network tab, the position payload will include the `discordMessageId`.

### 4. Close the Position

Close the position using the Exchange's UI (or wait for it to hit Take Profit / Stop Loss).

*   **What to look for**: The Go system will see the position disappear from the exchange. Look at the Go logs:
    ```
    [reconciler] Closed position_history ID 1 for bitunix:pos100 (Final PnL: 10.50)
    ```
*   **Database**: Refresh the `call_catch.position_history` table. The row's `status` will now be `CLOSED`, and the `realized_pnl` column will have captured the final profit/loss.

### 5. The Control Test (Manual Isolation)

To verify that your manual trading doesn't bleed into the bot's data:

*   Open a completely new position directly through the BitUnix or Phemex app (do **not** send a Discord message).
*   **What to look for**: The position will appear on your PWA dashboard, but the Go logs will **not** mention mapping the trade, and absolutely **no** row will be created in `position_history`. The system correctly isolated your manual behavior!

### 6. WebSocket Connection Test

To verify the Discord injector WebSocket:

1. Start the Go server: `sudo systemctl restart go-core`
2. Check health: `curl http://127.0.0.1:8080/api/health` — should show `discord_ws_clients: 0`
3. Open the insecure Chrome and inject the bookmarklet
4. Check health again — should show `discord_ws_clients: 1`
5. The ⚙️ button should have a green border and the modal should show "● WS"