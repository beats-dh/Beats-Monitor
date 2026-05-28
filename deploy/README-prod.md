# Penultima Monitor Production Deployment

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
D:\Server\Tools\flutter\bin\flutter.bat build web --release --base-href /beats-monitor/ --no-wasm-dry-run --pwa-strategy=none --no-tree-shake-icons
```

Publish `D:\Server\Beats-Monitor\build\web` to:

```text
/home/penultima/ultima-myaac/beats-monitor
```

Keep `--no-tree-shake-icons` for the monitor web build. The command center uses
Material and Material Design Icons across desktop and phone layouts; tree-shaken
icon fonts have produced blank toolbar/action buttons in installed PWAs.

Before publishing, verify the generated files in `build\web`, not only the
source files under `web\`. `index.html`, `cache_reset.js`, and
`flutter_bootstrap.js` must all contain the same build id, and the deployed
`cache_reset.js` hash should match `build\web\cache_reset.js`. A stale generated
`cache_reset.js` can leave installed phone PWAs on an older Dart bundle even when
`main.dart.js` has already been uploaded.

The build command with `--pwa-strategy=none` can overwrite
`build\web\flutter_service_worker.js` with a zero-byte file. For mobile/PWA cache
breaks, copy the checked-in self-cleaning worker back into the generated bundle
before publishing:

```powershell
Copy-Item D:\Server\Beats-Monitor\web\flutter_service_worker.js D:\Server\Beats-Monitor\build\web\flutter_service_worker.js -Force
```

Then include `flutter_service_worker.js` in the static upload. The expected
worker contains `cleanupAndReleaseClients()` and the same build id as the cache
reset/bootstrap files.

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
game is running code that contains the Penultima Monitor chat logger. The monitor
reads local chat, World/English chat, trade, help, and private messages.

Installed monitor notifications are client/PWA-side. After the user grants
browser notification permission, the web client watches the existing WebSocket
chat stream and shows a notification for every Help Chat message and every
private message addressed to `BEATS_MONITOR_REQUIRED_PLAYER_NAME` (`Waldir` in
the current production env). The client registers
`monitor_notification_worker.js` and uses its `showNotification` API for
installed phone PWAs, falling back to page notifications if worker registration
is not available. `cache_reset.js` clears old Flutter PWA caches once per static
build so installed phones can pick up the latest `/beats-monitor/` files without
a service restart. `web/flutter_bootstrap.js` also appends the same build id to
`main.dart.js`, which prevents an installed browser/PWA from reusing an older
HTTP-cached Dart bundle after a no-restart static deploy. This does not need a
game server restart because it consumes already-emitted monitor chat events.
True closed-app push delivery would require a separate Push API subscription and
backend push sender.

Runtime logs are read directly and read-only from `BEATS_MONITOR_LOG_ROOT`.
By default this is `/home/penultima/Penultima-Server/logs`, and the live view
tails `runtime.log` over the existing authenticated WebSocket connection. The UI
also lists the complete recursive log folder through `GET /server/logs` and
loads a selected file through `GET /server/logs/file/{encodedPath}`. This does
not control, signal, reload, or restart the game process.

When the live Node adapter cannot be restarted yet, publish
`web/beats_monitor_logs.php` with the static bundle. It is executed from
`/beats-monitor/beats_monitor_logs.php`, validates the same monitor bearer token
against the running API's `GET /api/v1/server/status`, then exposes the same
read-only recursive log list and tail snapshots from the server logs folder.
This bridge is a no-restart compatibility path for an older running API process;
keep it protected by the bearer-token validation and remove the dependency only
after the Node adapter with native `server/logs` routes is active.

If a static web build is published before the live API adapter has been updated,
the Logs screen and command-center runtime/log panels must try `GET /server/logs`
first, then fall back to the authenticated `web/beats_monitor_logs.php` bridge
when the running API still returns an unknown endpoint. The bridge exposes the
complete recursive folder and selected-file tail snapshots without restarting the
Node adapter. For no-restart verification, check the public PHP bridge with and
without a bearer token, and check the running process start time separately.

The branded web/PWA layout uses the Penultima assets under
`assets/branding/`. Keep the web manifest, favicon, `web/icons/*`, and Android
launcher icons regenerated from the same square Penultima logo when changing the
app icon. The authenticated home screen is a command-center shell: a desktop
left operation rail, top server-time/status cards, a hero command banner,
command tiles, runtime-log preview, log-file entry panel, and recent activity.
The phone dashboard intentionally has a separate mobile-only layout, not just a
scaled desktop rail. When changing the dashboard Dart code, bump the shared
build id in `web/index.html`, `web/cache_reset.js`,
`web/flutter_bootstrap.js`, and `web/flutter_service_worker.js` before
publishing so installed phones request the new `main.dart.js?v=<buildId>` bundle
and discard old PWA caches.

Outgoing monitor chat is queued in `beats_monitor_commands`. Keep
`BEATS_MONITOR_ALLOW_CHAT_SEND=false` unless the game server build containing the
command consumer has been deployed and the game process has restarted normally.
After that first activation, keep `BEATS_MONITOR_REQUIRE_FRESH_GAME_BRIDGE=false`
so normal no-restart builds do not falsely disable queuing just because the
binary on disk is newer than the running game process.
Because the monitor is not an in-game creature and has no map position, outgoing
local-chat selections are queued as World Chat (`chat_global`). Slash or bang
commands typed in any monitor chat mode are queued as `god_command` on the World
Chat channel, matching how the message appears when typed by the GOD character
in game.
God command execution uses the same queue with action `god_command`; keep
`BEATS_MONITOR_ALLOW_GOD_COMMANDS=false` unless the server build includes
`Game.playerSay` in Lua and the command must be enabled for the configured GOD
character.

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
