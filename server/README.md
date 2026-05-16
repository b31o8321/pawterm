# @cc/server

Fastify + WebSocket bridge between mobile/web clients and local Claude Code.

## 启动

```bash
# 在 workspace 根目录
pnpm install
pnpm dev:server   # 等价于 pnpm --filter @cc/server run dev
```

服务监听 `http://0.0.0.0:8765`。

## 配置

`config.example.json` → 复制为 `config.json`，编辑允许 App 访问的项目路径。

## 端点

| 路径 | 说明 |
|---|---|
| `GET /health` | 健康检查 |
| `GET /projects` | 项目白名单 |
| `GET /sessions?cwd=...` | SDK list_sessions |
| `GET /sessions/:id?cwd=...` | session info |
| `GET /sessions/:id/messages?cwd=...&limit&offset` | 历史消息 |
| `POST /sessions/:id/rename?cwd=...&title=...` | 重命名 |
| `POST /sessions/:id/tag?cwd=...&tag=...` | 标签 |
| `POST /sessions/:id/fork?cwd=...&title=...` | 分叉 |
| `DELETE /sessions/:id?cwd=...` | 删除 |
| `WS  /ws/session` | 聊天流式协议 |
| `WS  /ws/shell` | 终端 PTY 字节流 |

## 协议

见 `packages/shared/src/protocol.ts`。
