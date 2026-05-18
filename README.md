# PawTerm

> Control AI coding assistants from your phone.  
> Drive Claude Code (and more) while your dev machine does the actual work.

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
![Flutter](https://img.shields.io/badge/Flutter-Android-02569B?logo=flutter&logoColor=white)
![Node](https://img.shields.io/badge/node-%E2%89%A520-339933?logo=node.js&logoColor=white)

## What it is

A small bridge server runs on your dev machine (where `claude` CLI is installed). The Android app connects to it over your LAN or Tailscale and gives you a full mobile interface: chat, real terminal, session history, file browser.

```
  Your Mac / Linux box
  ┌────────────────────────────────┐
  │  PawTerm Server  :8765         │
  │  Claude Code CLI               │
  └──────────────┬─────────────────┘
                 │ WebSocket (LAN / Tailscale)
          ┌──────▼──────┐
          │ PawTerm App │
          │   Android   │
          └─────────────┘
```

## Install

### 1. Download the APK

Grab the latest `pawterm-*-arm64-v8a.apk` from [**Releases**](../../releases/latest) and install it on your Android phone.

> Enable **"Install unknown apps"** in Android settings if prompted.

### 2. Run the server on your dev machine

Requires Node 20+ and `claude` CLI logged in.

```bash
git clone https://github.com/airoucat/pawterm.git
cd pawterm
pnpm install
cp server/config.example.json server/config.json
# edit config.json — add your project paths to the whitelist
pnpm dev:server
# server listening on http://0.0.0.0:8765
```

### 3. Connect from the app

Open PawTerm → **Add connection** → enter your machine's IP:

| Network | Address |
|---------|---------|
| Same LAN | `http://192.168.x.x:8765` |
| Tailscale | `http://100.x.x.x:8765` |
| Android emulator | `http://10.0.2.2:8765` |

## Features

- **Chat** — full Claude conversation with streaming, thinking blocks, tool cards (Edit / Bash / Read / TodoWrite / …)
- **Terminal** — real PTY shell via node-pty + xterm; virtual keyboard bar with common keys
- **Sessions** — browse, resume, or start new Claude Code sessions per project
- **File browser** — view, open, share files from your project directories
- **Model switch** — swap between Opus / Sonnet / Haiku at runtime
- **Todo tracking** — live task progress chip with fireworks on completion 🎉

## Server config

`server/config.json` whitelists which directories the app can access:

```json
{
  "host": "0.0.0.0",
  "port": 8765,
  "permission_mode": "acceptEdits",
  "projects": [
    { "name": "my-project", "path": "~/code/my-project" }
  ]
}
```

## Build from source

```bash
# Server
pnpm install && pnpm dev:server

# Android app
cd app
flutter pub get
flutter run                  # debug on connected device
./scripts/build-apk.sh       # versioned release APK
```

## License

[MIT](LICENSE)
