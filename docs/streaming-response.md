# 流式响应与 Thinking 处理

> 解释 Claude Companion 服务端如何把 Anthropic API / Agent SDK 的事件流转成 WebSocket 帧，
> 客户端如何渲染，以及 thinking 内容的处理策略。
> 参考来源：`@anthropic-ai/claude-agent-sdk`、claude-code CLI 源码（`/Users/airoucat/workspace/shulex/claude-code-source-code`）。

---

## 1. Anthropic API 的原生流式事件（SSE）

Anthropic Messages API 在 `stream: true` 时返回 Server-Sent Events，事件类型如下：

| 事件 | 含义 |
| --- | --- |
| `message_start` | 一轮 assistant turn 开始，含 model、id |
| `content_block_start` | 一个 content block 开始（type 可能是 `text` / `thinking` / `tool_use` 等） |
| `content_block_delta` | 该 block 的增量数据（见下表的 delta.type） |
| `content_block_stop` | 该 block 结束 |
| `message_delta` | turn 元信息变更（stop_reason、usage） |
| `message_stop` | 整个 turn 结束 |
| `ping` | 保活心跳 |

`content_block_delta.delta` 的 type：

| delta.type | 字段 | 含义 |
| --- | --- | --- |
| `text_delta` | `text: string` | 普通文本片段（要显示在主流的） |
| `thinking_delta` | `thinking: string` | extended thinking 推理片段（**默认不显示**） |
| `input_json_delta` | `partial_json: string` | tool_use 输入参数的 JSON 增量 |
| `signature_delta` | `signature: string` | thinking 块的密码学签名（不是模型输出） |

---

## 2. claude-code CLI vs Agent SDK

| | claude-code CLI | Agent SDK (`@anthropic-ai/claude-agent-sdk`) |
| --- | --- | --- |
| 形态 | 终端 TUI（Ink 渲染） | Node 库，暴露 `query()` 异步迭代器 |
| 输入 | 交互式终端 | 程序调用 |
| 输出粒度 | 直接渲染到终端 | yield 出 SDKMessage 对象，**已经把 SSE 解析过** |
| 处理 thinking | **完全丢弃 thinking_delta**，只用其长度做 token 估计 | 仍会把 thinking 作为 content block 返回（开发者决定怎么用） |

**关键源码引用**：

`claude-code-source-code/src/utils/messages.ts:3048-3082`

```ts
case 'content_block_delta':
  switch (message.event.delta.type) {
    case 'text_delta': {
      const deltaText = message.event.delta.text
      onUpdateLength(deltaText)
      onStreamingText?.(text => (text ?? '') + deltaText)   // ← 写入 UI 主流
      return
    }
    case 'thinking_delta':
      onUpdateLength(message.event.delta.thinking)            // ← 只更新长度计数器
      return                                                  // ← 不写入主流
    case 'signature_delta':
      return                                                  // ← 直接丢弃
  }
```

**结论**：官方 claude-code CLI **不在主流里显示 thinking 内容**，这是产品决策。

---

## 3. 本项目的链路

```
┌────────────────────────────────────────────────────────────────────────────────────┐
│ Claude API (SSE)                                                                   │
│   ├─ content_block_delta { text_delta }                                            │
│   └─ content_block_delta { thinking_delta }                                        │
└──────────────────┬─────────────────────────────────────────────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────────────────────────────────────────────────┐
│ @anthropic-ai/claude-agent-sdk · query()                                           │
│   yield { type: 'stream_event', event: {...} }                                     │
│   yield { type: 'assistant', message: { content: [ContentBlock, ...] } }           │
│   yield { type: 'user',     message: { content: [tool_result, ...] } }             │
│   yield { type: 'result',   ...usage }                                             │
└──────────────────┬─────────────────────────────────────────────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────────────────────────────────────────────────┐
│ server/src/serialize.ts · messageToWire()                                          │
│   stream_event ▶ stream_block_start / stream_delta(kind=text|thinking) /           │
│                  stream_block_stop                                                  │
│   assistant   ▶ { type:'assistant', content:[{type:text|thinking|tool_use,...}] } │
│   user        ▶ { type:'user',     content:[{type:tool_result,...}] }              │
│   result      ▶ { type:'result', ...usage }                                        │
└──────────────────┬─────────────────────────────────────────────────────────────────┘
                   │  WebSocket /ws/session
                   ▼
┌────────────────────────────────────────────────────────────────────────────────────┐
│ app/lib/screens/tabs/chat_tab.dart                                                 │
│   • StreamBlockStart(kind='text')   → 新建 StreamingAssistant 缓冲                  │
│   • StreamDelta(kind='text')        → 追加缓冲                                      │
│   • StreamDelta(kind='thinking')    → 当前忽略（建议保持）                          │
│   • AssistantMsg                    → 替换 StreamingAssistant 为最终消息            │
└────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Thinking 内容的处理策略

**当前问题**：`app/lib/widgets/message_view.dart:104-126` 把 `ThinkingBlock` 渲染成了灰色斜体竖条样式，导致 thinking 内容直接出现在聊天主流。

**与 claude-code CLI 对齐的方案**：

| 方案 | 行为 | 推荐场景 |
| --- | --- | --- |
| **A. 完全隐藏** | 不渲染 ThinkingBlock | 严格对齐 claude-code，节省屏幕 |
| **B. 折叠显示**（本项目采用） | 默认显示 "💭 思考片段 ▸"，点击展开 | 节省空间但允许探查决策原因 |
| C. 暗淡显示 | 现在的样式 | 高度透明但占屏 |

我们选**方案 B**：折叠成一行标签，需要时一击展开。

---

## 5. 服务端继续传输 thinking 的理由

虽然客户端默认不展示，服务端仍然转发 `thinking_delta` 和 `thinking` content block，原因：

- 让客户端有选择权（不同 UI 端可以决定是否展示）
- 不需要服务端读取/解释具体内容
- 流量极小

如果将来要严格对齐 CLI 行为，可在 `serialize.ts` 第 64-71 行删掉 `thinking_delta` 分支，
以及 `extractContent` 中的 `'thinking'` 分支。

---

## 6. Spinner / 响应中状态

**claude-code CLI 的 spinner**（`src/components/Spinner/utils.ts:4-11`、`SpinnerGlyph.tsx:6-7`）：

```ts
// macOS
['·', '✢', '✳', '✶', '✻', '✽']
// 帧序列 = 正向 + 反向，共 12 帧（"开花-合上"循环）
const SPINNER_FRAMES = [...DEFAULT_CHARACTERS, ...[...DEFAULT_CHARACTERS].reverse()]
```

伴随显示的"动词"在 `src/constants/spinnerVerbs.ts`（500+ 个：`Accomplishing`, `Cogitating`, `Crystallizing`, ...）。每个 turn 随机挑一个，纯装饰。

本项目复刻方案在 `app/lib/widgets/cc_spinner.dart`：
- 同样的 6 字符序列 + 反向 = 12 帧
- 帧率 80ms/帧 → 整圈约 960ms
- 中文动词集（"思考中"、"推敲中"、"梳理中" 等）
- 同行展示 elapsed seconds 和 token 估计

---

## 7. 真实数据样本（来自实际 session JSONL）

下面的样例来自本机 `~/.claude/projects/{slug}/{session-id}.jsonl`，是 SDK 实际写入的格式。
**注意**：JSONL 的每行是一个 envelope（含 `parentUuid`/`timestamp`/`cwd` 等元数据），
里面的 `message` 字段才是 SDK 实际产出的 SDKMessage。我们的服务端 `serialize.ts` 处理的也是这个 `message`。

### 7.1 user · 用户纯文本输入

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": "nihao"
  },
  "promptId": "cce3e392-69d5-4146-8a21-e21a0cd58370",
  "uuid": "7dd4cad7-64ef-47d2-a78a-9fb440c6ad78",
  "timestamp": "2026-05-14T02:12:02.893Z",
  "permissionMode": "acceptEdits",
  "cwd": "/Users/airoucat/workspace/shulex/claude-companion",
  "sessionId": "1ae8e2d7-749a-41d7-97be-bce12b258929",
  "gitBranch": "main"
}
```

注意 `message.content` 是**字符串**（而不是数组）——这是用户纯文本输入的情况。

### 7.2 user · 斜杠命令（结构化 envelope）

用户在 CLI 里输入 `/model claude-sonnet-4-6` 会被记录成：

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": "<command-name>/model</command-name>\n            <command-message>model</command-message>\n            <command-args>claude-sonnet-4-6</command-args>"
  }
}
```

content 仍是字符串，但里面有 `<command-name>` / `<command-message>` / `<command-args>` 标签。
**App 端要识别这种内容，渲染成紧凑的命令 chip（已实现 `_CommandCallChip`），不能渲染成普通用户气泡。**

### 7.3 user · 命令输出 stdout

紧跟在斜杠命令后，CLI 会写入一条 stdout：

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": "<local-command-stdout>Set model to claude-sonnet-4-6</local-command-stdout>"
  }
}
```

类似的还有 `<local-command-stderr>...</local-command-stderr>` 表示命令报错。
**App 端渲染为 `_CommandOutputChip`（成功）或红色错误 chip。**

### 7.4 user · tool_result（工具返回值）

工具调用执行完成，CLI 把结果作为 user message 喂回模型：

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "tool_use_id": "toolu_01SwmQucevVGw25qpgpXKQF2",
        "type": "tool_result",
        "content": "README.md\napp\ndesign-preview.html\nnode_modules\npackage.json\n...",
        "is_error": false
      }
    ]
  },
  "toolUseResult": {
    "stdout": "README.md\napp\n...",
    "stderr": "",
    "interrupted": false,
    "isImage": false
  },
  "sourceToolAssistantUUID": "f39b4779-a37c-4a90-982f-249f1897bac0"
}
```

注意此时 `message.content` 是**数组**，元素 type = `tool_result`，对应一次 `tool_use`（通过 `tool_use_id` 关联）。
envelope 还有 `toolUseResult` 字段保留原始 stdout/stderr（仅本地 JSONL，不上报 API）。

### 7.5 assistant · 纯文本回复

```json
{
  "type": "assistant",
  "message": {
    "model": "claude-opus-4-7",
    "id": "msg_01KzfQmcySuG4BdT9jjWugEc",
    "role": "assistant",
    "content": [
      { "type": "text", "text": "你好！👋\n\n有什么我可以帮你的吗？..." }
    ],
    "stop_reason": "end_turn",
    "usage": {
      "input_tokens": 6,
      "cache_creation_input_tokens": 20685,
      "cache_read_input_tokens": 0,
      "output_tokens": 84
    }
  },
  "requestId": "req_011Cb1ei1WT1zB3rpFKhU4WT"
}
```

### 7.6 assistant · thinking 块（extended thinking）

```json
{
  "type": "assistant",
  "message": {
    "model": "claude-opus-4-7",
    "role": "assistant",
    "content": [
      {
        "type": "thinking",
        "thinking": "",
        "signature": "EokCClkIDRgCKkAnPL+yzj3gLJHrxrk..."
      }
    ],
    "stop_reason": "end_turn",
    "usage": { "output_tokens": 374, ... }
  }
}
```

关键字段：
- `thinking`：模型的推理内容（流式时通过 `thinking_delta.thinking` 增量传递）
- `signature`：thinking 的密码学签名（API 回传时必须原样保留，用于复用 thinking）
- 客户端 **完全不渲染** `thinking` 内容，参见 §4。

### 7.7 assistant · tool_use 块

```json
{
  "type": "assistant",
  "message": {
    "model": "claude-opus-4-7",
    "content": [
      {
        "type": "tool_use",
        "id": "toolu_01SwmQucevVGw25qpgpXKQF2",
        "name": "Bash",
        "input": {
          "command": "ls",
          "description": "List files in current directory"
        },
        "caller": { "type": "direct" }
      }
    ],
    "stop_reason": "tool_use"
  }
}
```

后续会跟一条 user message 携带对应 `tool_use_id` 的 `tool_result`（见 §7.4）。

### 7.8 类型分布（参考）

某个真实 session 的统计：

```
  12 assistant         (其中 9 个 text 块、2 个 thinking 块、1 个 tool_use 块)
  10 user              (9 条 string content、1 条 array 含 tool_result)
   7 attachment        (本地 hook 注入的上下文，不参与对话)
   4 last-prompt       (本地状态快照，不参与对话)
  18 queue-operation   (本地消息队列日志，不参与对话)
```

**`attachment` / `last-prompt` / `queue-operation` 都是 CLI 的本地状态记录**，
SDK 不会发出这些 type，服务端 `serialize.ts` 也不处理。客户端从历史 API 拿数据时，
会过滤掉这几类（只保留 `assistant` / `user` / `system` / `result`）。

---

## 8. 何时显示 spinner

| 时机 | 显示？ |
| --- | --- |
| 用户提交消息后等首个 token | ✅ |
| 模型流式输出文本中 | ✅（同时主流增长） |
| 工具调用执行中（pending tool_result） | ✅ |
| 收到 `result` 事件 | ❌（清掉 spinner） |
| 用户中断（interrupt） | ❌ |

由 `chat_tab.dart` 的 `_busy` 标志位控制，进 `_submit()` 时置 true，收到 `ResultMsg` 时置 false。
