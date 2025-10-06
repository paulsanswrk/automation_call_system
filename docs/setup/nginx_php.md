# Nginx & PHP Setup (Legacy)

> [!WARNING]
> **This setup is no longer required for Discord message ingestion.** As of March 2026, the Go backend handles all Discord message processing, AI analysis, and exchange order placement. The PHP/Nginx stack documented here is retained for reference only.

## What Was Replaced

| Before (PHP) | After (Go) |
|--------------|------------|
| `POST http://127.0.0.1/cc/server.php` | `POST http://127.0.0.1:8080/api/discord/message` |
| Nginx serving PHP-FPM on port 80 | Go server on port 8080 (direct) |
| `PHP/server.php` → TradeProcessor | `go-core/handlers/discord.go` → `pipeline/trade_processor.go` |
| Static file serving via Nginx | `GET /discord/injector.js` via Go static route |
| No WebSocket | `ws://127.0.0.1:8080/ws/discord` |

## Current Nginx Configuration

Nginx now only proxies requests from the public domain (`act2026.mooo.com`) to the Go server:

```nginx
# HTTPS server block
server {
    listen 443 ssl;
    server_name act2026.mooo.com;

    # SSL certs managed by certbot
    ssl_certificate /etc/letsencrypt/live/act2026.mooo.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/act2026.mooo.com/privkey.pem;

    # PWA static files
    root /home/ubuntu/projects/ACT_Call_Catch/ui_app/pwa/dist;
    index index.html;

    # WebSocket proxy (must appear before /api/)
    location /api/positions/ws {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    # API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Vue SPA fallback
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

> **Note**: The Discord injector connects directly to `127.0.0.1:8080` (not through Nginx) since it runs on the same machine. The Go server serves the injector JS file at `/discord/injector.js`.

## Legacy PHP Setup (Reference Only)

The previous setup used Nginx + PHP-FPM to serve `server.php` at `http://127.0.0.1/cc/server.php`. This is no longer active but the configuration is documented here for reference.

### Previous Nginx HTTP block (port 80)

```nginx
server {
    listen 80 default_server;
    server_name _;

    root /home/ubuntu/projects/ACT_Call_Catch/PHP;
    index server.php;

    location /cc/ {
        alias /home/ubuntu/projects/ACT_Call_Catch/PHP/;
        location ~ \.php$ {
            fastcgi_pass unix:/run/php/php8.4-fpm.sock;
            fastcgi_param SCRIPT_FILENAME $request_filename;
            include fastcgi_params;
        }
    }
}
```

### PHP-FPM service
- Service: `php8.4-fpm`
- Pool: `www` (default)
- Socket: `/run/php/php8.4-fpm.sock`

This PHP-FPM service can be stopped if no longer needed:
```bash
sudo systemctl stop php8.4-fpm
sudo systemctl disable php8.4-fpm
```
