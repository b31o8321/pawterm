# Claude Companion

> Mobile + web control surface for your local [Claude Code](https://docs.claude.com/en/docs/claude-code).
> Drive Claude from your phone or any browser while your dev machine does the actual work.

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
![Node](https://img.shields.io/badge/node-%E2%89%A520-339933?logo=node.js&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-Android%20%2B%20iOS-02569B?logo=flutter&logoColor=white)
![TypeScript](https://img.shields.io/badge/TypeScript-strict-3178C6?logo=typescript&logoColor=white)

## What it is

```
                ┌──────────────────────────────────┐
                │   server (Fastify, port 8765)   │
                │   REST  /health /projects /...   │
                │   WS    /ws/session /ws/shell    │
                └────┬─────────────────────┬───────┘
                     │ HTTP+WS             │ HTTP+WS
              ┌──────▼──────┐       ┌──────▼──────┐
              │ Flutter app │       │  Web admin  │
              │ Android/iOS │       │ port 5173   │
              └─────────────┘       └─────────────┘
```

A small bridge service runs on the machine where `claude` CLI is installed. It exposes
your Claude sessions over WebSocket, with the [`@anthropic-ai/claude-agent-sdk`](https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk)
driving the actual `claude` subprocess. Two clients consume that API:

- **Flutter app** for Android + iOS — chat, terminal (xterm + node-pty), session history.
- **Web admin** (Vite + React + Tailwind) — full-fledged PC dashboard for the same data.

Both clients share TypeScript protocol types via a small `@cc/shared` workspace package.

## Highlights

- **Streaming**: char-level deltas via the SDK's `includePartialMessages`, rendered live.
- **Sessions**: list / resume / fork / tag / delete via the SDK's session storage (no DB).
- **Terminal**: real PTY (`node-pty` on server + `xterm.js` / `xterm.dart` on clients).
- **Model switch**: change between Sonnet / Opus / Haiku at runtime.
- **Tool cards**: Edit / Bash / Read / Write / TodoWrite rendered as inline cards with diffs.
- **Cross-network**: Mac is the dev box; phone reaches it over Tailscale, WireGuard, or LAN.

## Repository layout

```
claude-companion/
├── server/                       Fastify backend (TypeScript)
│   └── src/
│       ├── index.ts              entry, route registration
│       ├── config.ts             project whitelist
│       ├── session-manager.ts    SDK query() wrapper
│       ├── ws-chat.ts            /ws/session handler
│       ├── ws-shell.ts           /ws/shell + node-pty
│       ├── sessions-api.ts       /sessions/* REST
│       ├── serialize.ts          SDK msg → wire JSON
│       └── logger.ts             pino + pretty mode
├── web/                          Vite + React PC admin
│   └── src/
│       ├── App.tsx
│       ├── api/                  REST + WS clients
│       ├── layout/               Sidebar / Header / PillBar
│       ├── tabs/                 Chat / Shell / Files / Git
│       └── tools/toolConfigs.ts  Tool card registry
├── app/                          Flutter mobile (Android + iOS)
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── theme.dart            AppTokens (dark + light)
│   │   ├── api/                  protocol + REST client
│   │   ├── state/                Riverpod stores
│   │   ├── screens/              Connections / MainShell / Git
│   │   └── widgets/              Sidebar / MessageView / ToolCard
│   └── scripts/build-apk.sh      versioned APK builder
├── packages/shared/              cross-client TS protocol types
└── docs/
    └── debug-pipeline.md         how to trace a message end-to-end
```

## Quick start

### Prereqs

- Node 20+ (`.nvmrc` pins 20; run `nvm use`)
- pnpm 9+
- `claude` CLI installed and logged in (run `claude` once interactively first)
- Flutter SDK (only if you want to build the mobile app)

### Backend + web admin

```bash
pnpm install
cp server/config.example.json server/config.json   # edit your project whitelist
pnpm dev                                            # runs server + web together
# or split:
pnpm dev:server     # http://localhost:8765
pnpm dev:web        # http://localhost:5173
```

### Mobile app

```bash
cd app
flutter run                       # picks first available device
# release build:
./scripts/build-apk.sh            # interactive version bump + outputs APKs under build/.../releases/<version>/
```

On Android emulator the host machine is `http://10.0.2.2:8765`. On real devices use your
machine's LAN IP, or its Tailscale `100.x.x.x` IP.

## Configuration

`server/config.json` controls which directories the clients can access (whitelist). Anything
outside these paths is rejected at the API layer.

```json
{
  "host": "0.0.0.0",
  "port": 8765,
  "permission_mode": "acceptEdits",
  "projects": [
    { "name": "my-project",   "path": "~/code/my-project" },
    { "name": "another-repo", "path": "~/code/another-repo" }
  ]
}
```

Environment variables:

| Var               | Default                              | Effect |
|-------------------|--------------------------------------|--------|
| `CC_CONFIG`       | `server/config.json`                 | Override config path |
| `CC_LOG_FORMAT`   | `pretty` (dev) / `json` (prod)       | Log output format |
| `CC_LOG_LEVEL`    | `info`                               | pino level |

## Protocol

All clients speak the same JSON protocol over WebSocket. Types live in
[`packages/shared/src/protocol.ts`](packages/shared/src/protocol.ts). When changing the
protocol, update three places: `protocol.ts`, `server/src/serialize.ts`, and
`app/lib/api/protocol.dart` (the Dart side has no codegen).

End-to-end tracing playbook: [`docs/debug-pipeline.md`](docs/debug-pipeline.md).

## Building APKs

```bash
cd app
./scripts/build-apk.sh
```

Interactive menu: keep current version, bump build number, patch / minor / major.
Outputs go to `app/build/app/outputs/flutter-apk/releases/<version>/`, with a
`latest.apk` symlink in the parent directory for convenience.

## Not yet implemented

- Files tab — directory browser + "@ this file" composer integration
- Git tab — diff / stage / commit on mobile
- Permission UI — interactive `can_use_tool` prompts
- File push from server to phone over Tailscale

## License

[MIT](LICENSE)
