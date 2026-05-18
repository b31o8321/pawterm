# pawterm-server

> Bridge server for [PawTerm](https://github.com/Airoucat233/pawterm) — lets the Android app control Claude Code on your dev machine.

## Quick start

```bash
npx pawterm-server
```

First run creates `~/.config/pawterm/config.json`. Edit it to add your project paths, then restart.

## Run as a background service (macOS / Linux)

```bash
npm install -g pawterm-server
pawterm-server install   # installs launchd agent (macOS) or systemd user unit (Linux)
                         # auto-starts at login, logs to ~/.config/pawterm/server.log
```

| Command | Description |
|---|---|
| `install` | Install and start as a background service |
| `uninstall` | Remove the background service |
| `start` | Start the service |
| `stop` | Stop the service |
| `restart` | Restart the service |
| `status` | Show whether the service is running |
| `update` | Update to latest version and restart |
| `logs [n]` | Tail service logs (default: last 50 lines) |
| `--version` | Print installed version |
| `help` | Show all commands |

## Requirements

- Node 20+
- [`claude` CLI](https://docs.anthropic.com/en/docs/claude-code) installed and logged in

## Config

`~/.config/pawterm/config.json`:

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

Override config path: `CC_CONFIG=/path/to/config.json npx pawterm-server`

## Connect

Open PawTerm app → Add connection → `http://<your-machine-ip>:8765`

Over Tailscale: `http://100.x.x.x:8765`

## API endpoints

| Path | Description |
|---|---|
| `GET /health` | Health check |
| `GET /projects` | Project whitelist |
| `GET /sessions?cwd=...` | List sessions |
| `GET /chat/:id/events` | SSE event stream |
| `WS  /ws/shell` | PTY byte stream |

Full protocol: [`packages/shared/src/protocol.ts`](https://github.com/Airoucat233/pawterm/blob/main/packages/shared/src/protocol.ts)
