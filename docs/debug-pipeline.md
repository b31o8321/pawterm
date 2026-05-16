# Claude Companion — 调试链路指南

本文讲清楚一条消息从 App 输入框出发，到最终在屏幕上"蹦字"的完整路径，以及每一段怎么加断点/看日志。

## 0. 全链路总览

```
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│   [Flutter App]                                                │
│   chat_tab.dart _submit()                                      │
│        │                                                       │
│        │ WS JSON: {"type":"user_message","text":"你好"}        │
│        ▼                                                       │
│   [server / WebSocket  /ws/session]                            │
│   ws-chat.ts  socket.on('message', ...)                       │
│        │                                                       │
│        │ session.pushUserMessage(text)                         │
│        ▼                                                       │
│   [session-manager.ts]                                         │
│   inputGen() async iterator yield                              │
│        │                                                       │
│        │ SDK 通过 inputGen 拿到下一条用户消息                  │
│        ▼                                                       │
│   [@anthropic-ai/claude-agent-sdk query()]                     │
│   spawns `claude` CLI 子进程 (stdio)                          │
│        │                                                       │
│        │ JSON over stdin/stdout                                │
│        ▼                                                       │
│   [claude CLI (Node binary)]                                   │
│        │                                                       │
│        │ HTTPS 流式                                            │
│        ▼                                                       │
│   [Anthropic API]                                              │
│        │                                                       │
│        │ Server-Sent Events 流回                               │
│        ▼                                                       │
│   [claude CLI stdout]                                          │
│        │                                                       │
│        │ JSON message_start / content_block_delta / ...        │
│        ▼                                                       │
│   [SDK iterator yields]                                        │
│   type: 'stream_event' | 'assistant' | 'result'                │
│        │                                                       │
│        ▼                                                       │
│   [serialize.ts messageToWire()]                               │
│   stream_event → stream_delta / stream_block_start / stop      │
│   assistant   → assistant (完整消息)                            │
│   result      → result (耗时 + cost)                            │
│        │                                                       │
│        │ JSON over WS                                          │
│        ▼                                                       │
│   [Flutter _onData]                                            │
│   StreamDelta  → 追加到 StreamingAssistant 缓冲                │
│   AssistantMsg → 替换 streaming 块为最终消息                   │
│   ResultMsg    → 显示耗时/cost 单行                            │
│        │                                                       │
│        │ setState → 重绘                                       │
│        ▼                                                       │
│   [_StreamingMessage / MessageView]                            │
│   Text widget 渲染字符                                          │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

## 1. 各段怎么加断点 / 看日志

### 1.1 Flutter App 端（发消息出口）

**位置**：`app/lib/screens/tabs/chat_tab.dart` 的 `_submit()` 和 `_onData()`

**加断点（IDEA Flutter）**：
- 右上角设备选 `Pixel 9 (mobile)`，点 **🐞 Debug**（不是 ▶ Run）
- 在 `_submit()` 内 `_channel?.sink.add(...)` 那行行号左边点一下设红点
- 在 `_onData(raw)` 第一行设断点
- 触发：App 里发消息

**加 print 日志（更轻量）**：
```dart
// _submit()
print('[SEND] $text');

// _onData()
print('[RECV] ${json['type']}: ${raw.length > 200 ? raw.substring(0, 200) : raw}');
```

print 输出在 **IDEA Run 面板**（Debug 时在 Console 标签）或 `flutter run` 终端里。

**DevTools 看 WebSocket 流**：
- `flutter run` 启动后打印 `http://127.0.0.1:9100?uri=...` 链接
- 浏览器打开 → Network 标签 → 过滤 WS → 看每一帧 JSON
- 这是看协议最直观的方式

### 1.2 WebSocket 协议层（看原始消息）

不用 App 也能调，**直接 wscat**：

```bash
npm i -g wscat
wscat -c ws://localhost:8765/ws/session
> {"type":"init","cwd":"~/path/to/claude-companion","model":"claude-sonnet-4-6"}
< {"type":"session_ready",...}
> {"type":"user_message","text":"hi"}
< {"type":"stream_block_start","index":0,"kind":"text"}
< {"type":"stream_delta","index":0,"kind":"text","text":"Hi"}
< {"type":"stream_delta","index":0,"kind":"text","text":"!"}
< {"type":"assistant","content":[...]}
< {"type":"result","duration_ms":1234,...}
```

发什么看什么，最纯粹。

### 1.3 Server 入口（ws-chat handler）

**位置**：`server/src/ws-chat.ts`

**IDEA Debug**：
1. Run → Edit Configurations → 选 npm 配置 `server`（之前配过的）
2. 点 **🐞 Debug**
3. 在 `socket.on('message', (raw) => ...)` 设断点
4. 触发：从 App 或 wscat 发消息

**日志（推荐用日志而非断点，更快）**：
```typescript
socket.on('message', (raw) => {
  // ...
  app.log.info({ type: msg.type, ...msg }, 'incoming chat msg');
});
```

`app.log` 是 fastify 内置 pino，输出会带 `[req-X]` 关联同一个连接的所有 log。

切到 JSON 日志方便机器解析：
```bash
CC_LOG_FORMAT=json pnpm dev:server | jq 'select(.msg=="incoming chat msg")'
```

### 1.4 SDK 调用 / claude CLI 子进程

**位置**：`server/src/session-manager.ts` 的 `start()`

**确认参数对**：
```typescript
start(): AsyncIterableIterator<any> {
  const options: Options = {
    cwd: this.cwd,
    permissionMode: this.permissionMode,
    includePartialMessages: true,
    ...(this.resume ? { resume: this.resume } : {}),
    ...(this.model ? { model: this.model } : {}),
  };
  console.log('[SDK options]', options); // 临时加
  this.iter = query({ prompt: this.inputGen.call(this), options });
  ...
}
```

**看 claude CLI 进程是否启动**（macOS）：
```bash
ps -ef | grep "@anthropic-ai/claude-agent-sdk-darwin-arm64/claude"
# 应该看到一个子进程，PPID 是 tsx 的 PID
```

**SDK 与 claude CLI 通信走 stdio**，相对黑盒。如果要看原始 JSON-RPC，可以用 `strace` / `dtrace`，但通常不需要。

### 1.5 Serialize 层（SDK → wire JSON）

**位置**：`server/src/serialize.ts` 的 `messageToWire()`

**最容易出错的环节**——SDK 返回的对象结构很复杂，转 wire 出问题流就断了。

**调试**：
```typescript
export function messageToWire(msg: any): any | null {
  console.log('[SDK msg]', msg.type, msg.event?.type ?? '');
  // ...
}
```

观察输出：
```
[SDK msg] system
[SDK msg] stream_event message_start
[SDK msg] stream_event content_block_start
[SDK msg] stream_event content_block_delta    ← 这些是字符级流
[SDK msg] stream_event content_block_delta
[SDK msg] stream_event content_block_stop
[SDK msg] stream_event message_delta
[SDK msg] stream_event message_stop
[SDK msg] assistant                            ← 最终完整消息
[SDK msg] result                               ← 这次 turn 的耗时 cost
```

如果只看到 `assistant` 没有 `stream_event`，说明 `includePartialMessages: true` 没生效。

### 1.6 Server → App（WS 推送）

**位置**：`server/src/ws-chat.ts` 的 `streamResponses()` → `send(wire)`

加日志：
```typescript
function send(payload: ChatServerMessage): void {
  if (socket.readyState !== 1) return;
  app.log.info({ type: payload.type }, 'sending to client');
  socket.send(JSON.stringify(payload));
}
```

### 1.7 App 接收 + 渲染

**位置**：`app/lib/screens/tabs/chat_tab.dart` `_onData()`

每个 case 加日志：
```dart
} else if (msg is StreamDelta) {
  print('[DELTA] idx=${msg.index} kind=${msg.kind} text="${msg.text}"');
  ...
}
```

## 2. 常见问题速查

| 症状 | 多半在哪一段断 | 怎么定位 |
|---|---|---|
| App "Connecting…" 不变 | WS 连不上 | 看 server 终端有没有 `incoming request GET /ws/session` |
| 收到 session_ready 但发消息没回 | SDK 卡了 / claude CLI 没启动 | `ps -ef | grep claude` 看子进程；server log 看错误 |
| 收到 result 但没 assistant 内容 | serialize 漏 case | 在 `messageToWire()` print 原始 msg.type |
| 没有字符级流式 | `includePartialMessages` 没传 / SDK 版本不支持 | server log 加 `console.log(options)` 验证 |
| 流式蹦字一闪就消失 | `assistant` 到达时 streaming 块没正确替换 | App `_onData` 的 AssistantMsg case 加 print |
| 资源耗尽 / Terminal 开不了 | PTY 泄漏（shell tab） | `lsof /dev/ttys* \| awk 'NR>1{print $1}' \| sort \| uniq -c` |

## 3. 快速验证全链路

启动 server（带彩色日志）：
```bash
cd ~/path/to/claude-companion
pnpm dev:server
```

新终端跑 wscat：
```bash
wscat -c ws://localhost:8765/ws/session
> {"type":"init","cwd":"~/path/to/claude-companion","model":"claude-sonnet-4-6"}
> {"type":"user_message","text":"用一句话说你是谁"}
```

应该看到：
1. server 终端打印 `[req-X] incoming request GET /ws/session`
2. wscat 收到 `session_ready`
3. wscat 持续收到 `stream_delta` 一串
4. wscat 收到 `assistant` 完整消息
5. wscat 收到 `result` cost 信息

任何一步缺失就知道断在哪。

## 4. 协议参考

完整 schema 见 `packages/shared/src/protocol.ts`。改协议时三处对齐：
1. `packages/shared/src/protocol.ts` 改类型
2. `server/src/serialize.ts` 改序列化逻辑
3. `app/lib/api/protocol.dart` 改 Dart 对应类
