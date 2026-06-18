# Penultima Monitor

Cross-platform Flutter client for monitoring an OTServBR-Global / Canary game server in real time. Connects over WebSocket to surface server status, system metrics, online and banned player lists, and in-game chat — from Android, iOS, Windows, or the web.

## Demo
https://github.com/user-attachments/assets/07e42c45-ea00-49c2-bfe9-b071b2ee2fef

> If the video does not play inline, [click here to download/watch](docs/demo.mp4).

## Features

- **Server status** — live uptime, version, player counts, world state.
- **System monitoring** — CPU usage per core, memory pressure, processor info.
- **Players** — online list with details, banned list with reasons/expiry, drill-down player info screen.
- **In-game chat bridge** — read and send messages to server channels from the client.
- **Auto-reconnect WebSocket** with configurable retry policy and connection-status popup.
- **Multi-platform** — Android, iOS, Windows desktop, Web.
- **i18n** — English and Portuguese (PT-BR), switchable at runtime.
- **Light/dark theme** with persisted user preference.
- **Secure credential storage** via `flutter_secure_storage`.

## Tech Stack

- **Flutter** (Dart SDK `^3.6.1`)
- **State**: `provider`
- **Networking**: `web_socket_channel`, `http`, `dio`
- **Storage**: `flutter_secure_storage`, `shared_preferences`
- **Platform**: `package_info_plus`, `device_info_plus`, `permission_handler`, `path_provider`

## Project Structure

```
lib/
  constants/        App-wide constants
  l10n/             Localization (en, pt) + AppLocalizations delegate
  models/           Data models (system_data, server_status, events, websocket_events)
  providers/        ChangeNotifier providers (auth, theme, locale)
  screens/          Screens (home, login, monitor, chat, server_info, config,
                            online_players, banned_players, player_info)
  services/         api_service, auth_service, config_service, websocket_service,
                    download_service, platform_service, update_service
  widgets/          Reusable UI (cards, popups, transitions)
  main.dart         Entry point
android/  ios/  windows/  web/   Platform-specific projects
```

## Getting Started

### Prerequisites

- Flutter SDK `>= 3.6.1` ([install guide](https://docs.flutter.dev/get-started/install))
- Platform toolchains as needed:
  - Android Studio / Android SDK for Android builds
  - Xcode for iOS builds (macOS only)
  - Visual Studio with C++ desktop workload for Windows

### Setup

```bash
git clone https://github.com/beats-dh/Beats-Monitor.git
cd Beats-Monitor
flutter pub get
```

### Run

```bash
flutter run                 # Auto-pick connected device
flutter run -d windows      # Windows desktop
flutter run -d chrome       # Web
flutter run -d <emulator>   # Android / iOS emulator
```

### Build

```bash
flutter build apk --release           # Android APK
flutter build appbundle --release     # Android App Bundle
flutter build ios --release           # iOS
flutter build windows --release       # Windows
flutter build web --release --base-href /beats-monitor/ --no-wasm-dry-run  # Production web
```

## Configuration

The server endpoint is configurable from the **Config** screen at runtime (persisted via `flutter_secure_storage`). Default values live in `lib/services/config_service.dart`:

| Setting              | Default              | Description                                     |
| -------------------- | -------------------- | ----------------------------------------------- |
| `baseUrl`            | `177.23.187.59:8081` | `host:port` of the Canary backend               |
| `autoReconnect`      | `true`               | Reconnect automatically on socket drop          |
| `reconnectAttempts`  | `5`                  | Max reconnect attempts before giving up         |

The client derives the API and WebSocket URLs as:

- API: `http://{baseUrl}/api/v1`
- WebSocket: `ws://{baseUrl}/ws`

## Backend

Penultima Monitor talks to a Canary-based OTServBR-Global server (C++23 MMORPG engine). The server exposes a JSON WebSocket and a REST API consumed by this client. See the [Canary repository](https://github.com/opentibiabr/canary) for backend setup.

## Branches

- **`main`** — stable release branch.

Branch names are prefixed with `penultima-monitor` per project convention.

## License

[PolyForm Noncommercial 1.0.0](LICENSE).

You are free to use, modify, and redistribute this software for any
**noncommercial** purpose. **Selling or buying this software — in whole, in
part, or as a derivative work — is not permitted; both the seller and the
buyer would be in violation of this license.** See the [LICENSE](LICENSE)
file for the full terms.
