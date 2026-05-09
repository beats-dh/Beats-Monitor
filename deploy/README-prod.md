# Beats Monitor Production Deployment

Production uses two deployable pieces:

1. Static Flutter web build served at `/beats-monitor/`.
2. Hardened Node API adapter served behind HTTPS at `/beats-monitor-api/`.

The Flutter build defaults to same-origin routing:

- API: `/beats-monitor-api/api/v1`
- WebSocket: `/beats-monitor-api/ws`

The adapter intentionally does not start, stop, or restart the game server. Mutating endpoints are disabled by default.

## Build

Run locally:

```powershell
D:\Server\Tools\flutter\bin\flutter.bat build web --release --base-href /beats-monitor/ --no-wasm-dry-run
```

Publish `D:\Server\Beats-Monitor\build\web` to:

```text
/home/penultima/ultima-myaac/beats-monitor
```

## Backend Files

Copy these files to the game host:

```text
deploy/beats-monitor-api.js -> /home/penultima/beats-monitor-api/beats-monitor-api.js
deploy/beats-monitor-api.env.example -> /home/penultima/beats-monitor-api/.env.example
deploy/beats-monitor-api.service -> /home/penultima/beats-monitor-api/beats-monitor-api.service
deploy/nginx-beats-monitor.conf -> /home/penultima/beats-monitor-api/nginx-beats-monitor.conf
```

Create `/home/penultima/beats-monitor-api/.env` from the example. Keep it mode `600`.
The service file expects a portable Node runtime at:

```text
/home/penultima/beats-monitor-api/node/bin/node
```

For game-account login, enable these values in `.env`:

```text
BEATS_MONITOR_GAME_AUTH=true
BEATS_MONITOR_REQUIRED_PLAYER_NAME=Waldir
BEATS_MONITOR_MIN_GROUP_ID=6
```

This does not store the game password. The adapter checks the existing `accounts`
password hash in MySQL and only accepts the account when the configured player is
a GOD/staff character.

Chat history/live chat is read from `beats_monitor_chat_messages`. The server
fills that table from the chat channel scripts and the game speech path after the
game is running code that contains the Beats Monitor chat logger. The monitor
reads local chat, World/English chat, trade, help, and private messages.

Outgoing monitor chat is queued in `beats_monitor_commands`. Keep
`BEATS_MONITOR_ALLOW_CHAT_SEND=false` unless the game server build containing the
command consumer has been deployed and the game process has restarted normally.

## Activation

Activation requires normal prod service steps:

```bash
sudo install -m 0644 /home/penultima/beats-monitor-api/beats-monitor-api.service /etc/systemd/system/beats-monitor-api.service
sudo install -m 0644 /home/penultima/beats-monitor-api/nginx-beats-monitor.conf /etc/nginx/snippets/beats-monitor.conf
sudo nginx -t
sudo systemctl daemon-reload
sudo systemctl enable --now beats-monitor-api.service
sudo systemctl reload nginx
```

Do not run those commands during game uptime unless you intentionally want to activate the monitor service and reload nginx.
