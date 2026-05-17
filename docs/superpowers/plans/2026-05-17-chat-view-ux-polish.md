# Chat 视图 UX 完善 实现 Plan（Spec A）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 [Spec A](../specs/2026-05-17-chat-view-ux-polish-design.md) 的五项 chat 视图改进落地：按钮黑白风、附件上传、tool 输出/输入对象 JSON 修复、AskUserQuestion 交互渲染、Chat 传输层换 SSE+REST（终端 WS 不变）。

**Architecture:** Server 侧在现有 Fastify + claude-agent-sdk 上做三件事：(1) 加 `/upload` 端点；(2) 把 chat 从 WS 改成 REST + SSE（含 Last-Event-ID 续传 ring buffer）；(3) 加一个自定义 MCP server (`ask-user-question`) 把 tool handler 挂起+等客户端回答。Client 侧扩展 `_Composer` + 新增 `AskUserQuestionWidget` + 自己写一个 ~80 行 SSE 客户端。引入 vitest 给 server 纯函数加最小测试。

**Tech Stack:** Flutter (Dart), TypeScript + Fastify 5, `@anthropic-ai/claude-agent-sdk` 0.2.141, vitest（新引入）, `@fastify/multipart`（新引入）, `file_picker` Flutter pub 包（新引入）。SSE 客户端自实现，不引第三方包。

---

## 文件结构

**新建：**
- `server/src/event-buffer.ts` — SSE 事件 ring buffer 类（per session 1000-event 缓冲 + Last-Event-ID 续传支持）
- `server/src/chat-rest.ts` — Chat REST 路由 + SSE 端点（替代 ws-chat.ts）
- `server/src/upload.ts` — `POST /upload` Fastify route handler
- `server/src/ask-user-tool.ts` — `AskUserQuestionRegistry` 类 + `makeAskUserMcpServer()` 工厂
- `server/src/__tests__/serialize.test.ts` — `normalizeToolResultContent` 快照测试
- `server/src/__tests__/event-buffer.test.ts` — `EventBuffer` 单元测试
- `server/src/__tests__/ask-user-tool.test.ts` — `AskUserQuestionRegistry` 单元测试
- `server/vitest.config.ts` — vitest 配置
- `app/lib/api/upload_api.dart` — Flutter 上传 HTTP 客户端
- `app/lib/api/sse_client.dart` — 轻量 SSE 客户端（~80 行，自实现）
- `app/lib/api/chat_api.dart` — Chat REST 客户端（start/message/interrupt/setModel/setPermissionMode/answerQuestion/close）
- `app/lib/widgets/ask_user_question.dart` — `AskUserQuestionWidget`（live + answered 双态）

**修改：**
- `server/package.json` — 加 `vitest` (dev) + `@fastify/multipart` + `zod` 显式依赖
- `server/src/serialize.ts` — 重写 `normalizeToolResultContent`
- `server/src/index.ts` — 注册 multipart + `/upload` + `chat-rest`；保留 `ws-chat`（Task 2b 暂时双栈）；Task 2c 末尾移除 ws-chat
- `server/src/session-manager.ts` — 注入 askRegistry + mcpServers + `answerQuestion()` 方法（transport-agnostic）
- `server/src/ws-chat.ts` — **Task 2c 删除**（Spec A 之前先保留双栈一次 commit）
- `packages/shared/src/protocol.ts` — 删除 `ChatClientMessage` union；新增 REST 请求/响应类型；保留 ChatEvent 类型；新增 `AnswerQuestionRequest` 等
- `app/pubspec.yaml` — 加 `file_picker: ^8.0.0` 依赖
- `app/lib/screens/tabs/chat_tab.dart` — 改造 `_ChatTabState`（去 WS，用 SseClient + ChatApi）+ `_SendOrStopButton` 黑白风 + `_Composer` 加附件
- `app/lib/widgets/message_view.dart` — `ToolUseBlock` 分发新增 AskUserQuestion 分支
- `app/lib/widgets/tool_call_card.dart` — 新增 `_JsonBlock` + `_renderBody` default 分支条件切换

---

## Pre-flight：清理工作树

工作树当前有未提交的改动（早先的气泡 / 主题改动 + 用户自己的 `_pending` 队列）。开工前必须先处理。

- [ ] **Step 0.1: 看当前未提交改动**

Run: `git status --short`

Expected output（应该看到这类输出）:
```
 M app/lib/api/protocol.dart
 M app/lib/screens/tabs/chat_tab.dart
 M app/lib/theme.dart
 M app/lib/widgets/message_view.dart
 M app/lib/widgets/...
 M packages/shared/src/protocol.ts
 M server/src/ws-chat.ts
```

- [ ] **Step 0.2: 决定如何处理**

如果这些是之前讨论过的 "气泡柔化 + theme 选择色 + 用户的 _pending 队列" —— 先单独 commit 一次再开工：

```bash
git add app/lib/widgets/message_view.dart app/lib/theme.dart app/lib/screens/tabs/chat_tab.dart
git commit -m "feat(chat): soften user bubble, set text selection theme, add pending queue"
```

如果还有别的杂项，按你的判断分别 commit 或 stash。

**继续之前** 必须满足：`git status --short` 输出为空（或只剩明确无关此 plan 的内容）。

- [ ] **Step 0.3: 锁定 spec 已合并**

Run: `git log --oneline -3`

Expected: 看到 `docs(spec): add chat-view UX polish design (Spec A)` 这个 commit。

---

## Task 1: §3 tool_result JSON 修复 + 引入 vitest

**目标**：先做最小、收益最直接的一项。引入 vitest 顺便给序列化层兜底测试。

**Files:**
- Modify: `server/package.json`
- Create: `server/vitest.config.ts`
- Create: `server/src/__tests__/serialize.test.ts`
- Modify: `server/src/serialize.ts:150-162`

### Step 1.1: 装 vitest

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion/server
pnpm add -D vitest
```

Expected: `package.json` 出现 `"vitest": "^x.y.z"` 在 `devDependencies` 里。

### Step 1.2: 加 vitest 配置

- [ ] Create `server/vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['src/**/__tests__/*.test.ts'],
    environment: 'node',
  },
});
```

### Step 1.3: 加 test 脚本

- [ ] 修改 `server/package.json`，在 `scripts` 里加：

```json
"test": "vitest run",
"test:watch": "vitest"
```

最终 `scripts` 字段应该是（基于现有内容增量）：
```json
"scripts": {
  "dev": "tsx watch src/index.ts",
  "build": "tsc -p tsconfig.json",
  "start": "node dist/index.js",
  "typecheck": "tsc --noEmit",
  "test": "vitest run",
  "test:watch": "vitest",
  "postinstall": "node scripts/fix-pty-perms.cjs"
}
```

### Step 1.4: 写失败测试

- [ ] Create `server/src/__tests__/serialize.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { messageToWire } from '../serialize.js';

describe('normalizeToolResultContent (via messageToWire user msg)', () => {
  function wireToolResultContent(content: unknown) {
    const wire = messageToWire({
      type: 'user',
      message: {
        role: 'user',
        content: [{ type: 'tool_result', tool_use_id: 'x', content, is_error: false }],
      },
    });
    return (wire.content[0] as any).content;
  }

  it('passes plain strings through unchanged', () => {
    expect(wireToolResultContent('hello')).toBe('hello');
  });

  it('preserves text blocks with string text', () => {
    expect(wireToolResultContent([{ type: 'text', text: 'abc' }])).toEqual([
      { type: 'text', text: 'abc' },
    ]);
  });

  it('JSON-stringifies object-shaped text fields (this is the [object Object] bug)', () => {
    const result = wireToolResultContent([{ type: 'text', text: { a: 1, b: [2, 3] } }]);
    expect(result).toEqual([
      { type: 'text', text: '{\n  "a": 1,\n  "b": [\n    2,\n    3\n  ]\n}' },
    ]);
  });

  it('JSON-stringifies entire object items without text field', () => {
    const result = wireToolResultContent([{ some: 'data', nested: { x: 1 } }]);
    expect(result).toEqual([
      {
        type: 'text',
        text: '{\n  "some": "data",\n  "nested": {\n    "x": 1\n  }\n}',
      },
    ]);
  });

  it('JSON-stringifies whole-object content (non-array, non-string)', () => {
    expect(wireToolResultContent({ k: 'v' })).toBe('{\n  "k": "v"\n}');
  });

  it('preserves image content blocks as-is', () => {
    const img = { type: 'image', source: { data: 'b64...', media_type: 'image/png' } };
    expect(wireToolResultContent([img])).toEqual([img]);
  });

  it('handles null content', () => {
    expect(wireToolResultContent(null)).toBeNull();
  });
});
```

### Step 1.5: 跑测试确认失败

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion/server
pnpm test
```

Expected: 5/7 测试失败（"JSON-stringifies object-shaped text fields"、"JSON-stringifies entire object items"、"JSON-stringifies whole-object content"、"preserves image content blocks"、和 null 之外的对象 case），因为当前实现用 `String(obj)`。

### Step 1.6: 修 serialize.ts

- [ ] Modify `server/src/serialize.ts`，把 `normalizeToolResultContent` 整体替换为：

```ts
function normalizeToolResultContent(content: unknown): any {
  if (content == null) return null;
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content.map((item: any) => {
      if (item && typeof item === 'object' && item.type === 'image') {
        // Preserve image blocks as-is — they have base64 source we shouldn't stringify.
        return item;
      }
      if (item && typeof item === 'object' && 'text' in item) {
        const t = item.text;
        const text = typeof t === 'string' ? t : JSON.stringify(t, null, 2);
        return { type: 'text', text };
      }
      // Anything else (including raw JSON objects from MCP tools): stringify whole item.
      return { type: 'text', text: JSON.stringify(item, null, 2) };
    });
  }
  if (typeof content === 'object') {
    return JSON.stringify(content, null, 2);
  }
  return String(content);
}
```

### Step 1.7: 跑测试确认通过

- [ ] Run:

```bash
pnpm test
```

Expected: 7/7 PASS.

### Step 1.8: 跑 typecheck

- [ ] Run:

```bash
pnpm typecheck
```

Expected: 无 error。

### Step 1.9: Commit

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion
git add server/package.json server/vitest.config.ts server/src/__tests__/serialize.test.ts server/src/serialize.ts
git commit -m "$(cat <<'EOF'
fix(serialize): JSON.stringify object tool_result content

Replaces String(obj) with JSON.stringify(obj, null, 2) so MCP tools
returning structured data no longer render as "[object Object]" in
the client. Image blocks are preserved as-is.

Adds vitest + snapshot tests for normalizeToolResultContent.
EOF
)"
```

---

## Task 1b: §3b Client tool_use input pretty-JSON 渲染

**目标**：自定义 / MCP 工具的 input 含嵌套 Map/List 时，渲染为美化 JSON 代码块；浅层 input 保留现有内联键值显示。

**Files:**
- Modify: `app/lib/widgets/tool_call_card.dart`（顶部 import、`_renderBody` default 分支、文件末尾新增 `_JsonBlock`）

### Step 1b.1: 顶部加 dart:convert import

- [ ] 在 `app/lib/widgets/tool_call_card.dart` 顶部 import 区追加（如果还没有）：

```dart
import 'dart:convert';
```

### Step 1b.2: 改 _renderBody 的 default 分支

- [ ] 找到 `_renderBody` 方法（grep `Widget _renderBody`），把 default 分支替换：

原代码：
```dart
default:
  return _KeyValueList(map: input);
```

替换为：
```dart
default:
  final hasNested = input.values.any((v) => v is Map || v is List);
  return hasNested
      ? _JsonBlock(value: input)
      : _KeyValueList(map: input);
```

### Step 1b.3: 在文件末尾新增 _JsonBlock 组件

- [ ] 把这段加在 `_KeyValueList` 类下面（约 370 行后）：

```dart
/// Pretty-JSON 代码块。用于嵌套结构（Map/List）的 tool input / 通用对象展示。
/// 与 _outputBody 相同的视觉规格（黑底 + monospace + textMuted）。
class _JsonBlock extends StatelessWidget {
  final Object? value;
  const _JsonBlock({required this.value});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    const enc = JsonEncoder.withIndent('  ');
    // jsonEncode 对非 JSON-safe 值（如 DateTime）会抛；保护一下
    String text;
    try {
      text = enc.convert(value);
    } catch (_) {
      text = value.toString();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.borderSubt, width: 0.5),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: t.textMuted,
          height: 1.5,
        ),
      ),
    );
  }
}
```

### Step 1b.4: flutter analyze

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion/app
flutter analyze lib/widgets/tool_call_card.dart
```

Expected: 无 error。

### Step 1b.5: 手动 smoke

- [ ] 启 server + app
- [ ] 让 Claude 调一个嵌套 input 的工具（最方便的是：让它调 `mcp__ask-user-question__AskUserQuestion` —— Task 8 之后才有；或者临时让 Claude 用 `WebFetch` 传一个嵌套 prompt 对象）
- [ ] 当 tool input 嵌套时，期望看到 JSON 代码块（多行、缩进 2 格）
- [ ] 当 tool input 是浅层（如 `{ pattern: '...', path: '...' }`），期望仍是 inline `key: value` 形式

Note: 这一步在 Task 1 提交之后、AskUserQuestion 还没就绪之前可以暂时只用现有工具做 smoke（例如让 Claude 用 `WebFetch` 配置某些嵌套参数）。彻底 e2e 验证留到 Task 12。

### Step 1b.6: Commit

- [ ] Run:

```bash
git add app/lib/widgets/tool_call_card.dart
git commit -m "feat(chat): pretty-JSON rendering for nested tool_use input"
```

---

## Task 2: §1 发送 / 停止按钮黑白风改造

**目标**：替换 `_SendOrStopButton` 的视觉规格。无 server / 协议改动。

**Files:**
- Modify: `app/lib/screens/tabs/chat_tab.dart::_SendOrStopButton`（当前约在 990-1031 行）

### Step 2.1: 替换 _SendOrStopButton 实现

- [ ] Open `app/lib/screens/tabs/chat_tab.dart`，找到 `_SendOrStopButton` 类（grep `class _SendOrStopButton`），整段替换为：

```dart
/// 输入框右侧的 40×40 圆形按钮（黑白主题，对照 cxclaw）。
/// - busy=false → 发送上箭头
/// - busy=true  → 停止方块（同一种背景，仅图标变）
/// - 不可用    → 浅灰
class _SendOrStopButton extends StatefulWidget {
  final bool busy;
  final bool canSend;
  final VoidCallback onSubmit;
  final VoidCallback onStop;
  const _SendOrStopButton({
    required this.busy,
    required this.canSend,
    required this.onSubmit,
    required this.onStop,
  });

  @override
  State<_SendOrStopButton> createState() => _SendOrStopButtonState();
}

class _SendOrStopButtonState extends State<_SendOrStopButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    // 主题色：亮模式黑底，暗模式近白底。按下时 / 不可用时颜色降级。
    final Color bg;
    final Color fg;
    if (!widget.canSend && !widget.busy) {
      bg = dark ? t.borderSubt : const Color(0xFFD0D5DD);
      fg = dark ? t.textDim : Colors.white;
    } else {
      bg = dark ? t.text : const Color(0xFF101828);
      fg = dark ? const Color(0xFF0B1210) : Colors.white;
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.busy
          ? widget.onStop
          : (widget.canSend ? widget.onSubmit : null),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.busy
              ? Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: fg,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              : Icon(Icons.arrow_upward_rounded, size: 18, color: fg),
        ),
      ),
    );
  }
}
```

### Step 2.2: 跑 flutter analyze 确认无 error

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion/app
flutter analyze lib/screens/tabs/chat_tab.dart
```

Expected: 无 error。若有 `_attempting` 未使用的 warning，是预存在的，跟本任务无关。

### Step 2.3: 手动 smoke

- [ ] Run app（`flutter run`），亮 / 暗模式各看一遍：
  - 没输入文字 → 按钮浅灰
  - 输入文字 → 按钮黑/白主色，箭头清晰
  - 发送中 → 按钮变方块（同色），点击可中断
  - 按下时有 scale 反馈

### Step 2.4: Commit

- [ ] Run:

```bash
git add app/lib/screens/tabs/chat_tab.dart
git commit -m "style(composer): black-white send/stop button (cxclaw-style)"
```

---

## Task 2b: §5 Server — Chat REST + SSE 迁移（与 WS 双栈）

**目标**：把 chat 协议从 WS 改为 REST + SSE，含 Last-Event-ID 续传。**保留 `ws-chat.ts` 一个 commit 周期**，让 client 迁移期间 main 不挂。

**Files:**
- Create: `server/src/event-buffer.ts`
- Create: `server/src/chat-rest.ts`
- Create: `server/src/__tests__/event-buffer.test.ts`
- Modify: `server/src/index.ts`（注册 chat-rest，保留 ws-chat）

### Step 2b.1: 写 EventBuffer 测试

- [ ] Create `server/src/__tests__/event-buffer.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { EventBuffer } from '../event-buffer.js';

describe('EventBuffer', () => {
  it('assigns monotonically increasing IDs', () => {
    const b = new EventBuffer(10);
    expect(b.push('a', {}).id).toBe(1);
    expect(b.push('b', {}).id).toBe(2);
    expect(b.push('c', {}).id).toBe(3);
  });

  it('drops oldest when full', () => {
    const b = new EventBuffer(3);
    b.push('a', {}); // id=1
    b.push('b', {}); // id=2
    b.push('c', {}); // id=3
    b.push('d', {}); // id=4, drops id=1
    expect(b.oldestId).toBe(2);
    expect(b.newestId).toBe(4);
  });

  it('since(0) returns all events', () => {
    const b = new EventBuffer(10);
    b.push('a', { x: 1 });
    b.push('b', { x: 2 });
    expect(b.since(0)?.length).toBe(2);
  });

  it('since(newestId) returns empty', () => {
    const b = new EventBuffer(10);
    b.push('a', {});
    b.push('b', {});
    expect(b.since(2)).toEqual([]);
  });

  it('since(lastId older than oldest) returns null (gap)', () => {
    const b = new EventBuffer(3);
    b.push('a', {}); b.push('b', {}); b.push('c', {}); b.push('d', {});
    // oldest is id=2, requesting since(0) means we need id=1 which is gone
    expect(b.since(0)).toBeNull();
  });

  it('empty buffer: oldestId null, newestId 0', () => {
    const b = new EventBuffer(10);
    expect(b.oldestId).toBeNull();
    expect(b.newestId).toBe(0);
  });
});
```

### Step 2b.2: 写 EventBuffer 实现

- [ ] Create `server/src/event-buffer.ts`:

```ts
export interface BufferedEvent {
  id: number;
  type: string;
  data: unknown;
}

export class EventBuffer {
  private events: BufferedEvent[] = [];
  private nextId = 1;
  private readonly maxSize: number;

  constructor(maxSize = 1000) {
    this.maxSize = maxSize;
  }

  push(type: string, data: unknown): BufferedEvent {
    const event: BufferedEvent = { id: this.nextId++, type, data };
    this.events.push(event);
    if (this.events.length > this.maxSize) {
      this.events.shift();
    }
    return event;
  }

  /**
   * Returns events with id > lastId.
   * Returns null if lastId is older than our oldest buffered event (gap).
   * Returns [] if lastId === newestId or buffer empty.
   */
  since(lastId: number): BufferedEvent[] | null {
    if (this.events.length === 0) return [];
    const oldest = this.events[0].id;
    if (lastId + 1 < oldest) return null;
    return this.events.filter((e) => e.id > lastId);
  }

  get oldestId(): number | null {
    return this.events.length > 0 ? this.events[0].id : null;
  }

  get newestId(): number {
    return this.nextId - 1;
  }
}
```

### Step 2b.3: 跑 EventBuffer 测试

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion/server
pnpm test
```

Expected: 7（serialize）+ 6（event-buffer）= 13 PASS。

### Step 2b.4: 写 chat-rest.ts

- [ ] Create `server/src/chat-rest.ts`:

```ts
import type { FastifyInstance } from 'fastify';
import { resolve } from 'node:path';

import type { PermissionMode } from '@cc/shared';

import { isPathAllowed, settings } from './config.js';
import { EventBuffer } from './event-buffer.js';
import { messageToWire } from './serialize.js';
import { ChatSession } from './session-manager.js';

interface SessionEntry {
  session: ChatSession;
  buffer: EventBuffer;
  graceTimer?: NodeJS.Timeout;
  writers: Set<{ write: (s: string) => void; end: () => void }>;
}

const sessions = new Map<string, SessionEntry>();
const GRACE_MS = 30_000;
const HEARTBEAT_MS = 15_000;

function makeSessionId(): string {
  return Math.random().toString(36).slice(2) + Date.now().toString(36);
}

function broadcast(entry: SessionEntry, type: string, data: unknown): void {
  const ev = entry.buffer.push(type, data);
  const payload = `id: ${ev.id}\nevent: ${type}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const w of entry.writers) {
    try { w.write(payload); } catch { /* writer gone */ }
  }
}

function cancelGrace(entry: SessionEntry): void {
  if (entry.graceTimer) {
    clearTimeout(entry.graceTimer);
    entry.graceTimer = undefined;
  }
}

function startGrace(id: string, entry: SessionEntry): void {
  if (entry.graceTimer) return;
  entry.graceTimer = setTimeout(() => {
    closeSession(id);
  }, GRACE_MS);
}

function closeSession(id: string): void {
  const entry = sessions.get(id);
  if (!entry) return;
  cancelGrace(entry);
  entry.session.close();
  for (const w of entry.writers) {
    try { w.end(); } catch { /* */ }
  }
  sessions.delete(id);
}

async function consumeSdk(id: string, entry: SessionEntry): Promise<void> {
  try {
    const iter = entry.session.start();
    for await (const sdkMsg of iter) {
      const wire = messageToWire(sdkMsg);
      if (wire) {
        const stamped = { ...wire, timestamp: Date.now() };
        broadcast(entry, (wire as any).type, stamped);
      }
    }
  } catch (err) {
    broadcast(entry, 'error', { type: 'error', message: (err as Error).message });
  }
}

export async function registerChatRest(app: FastifyInstance): Promise<void> {
  app.post<{ Body: { cwd?: string; permission_mode?: PermissionMode; resume?: string; model?: string } }>(
    '/chat/start',
    async (req, reply) => {
      const body = req.body ?? {};
      if (!body.cwd) { reply.code(400); return { error: 'cwd required' }; }
      const cwd = resolve(body.cwd);
      if (!isPathAllowed(cwd)) { reply.code(403); return { error: `Project not allowed: ${cwd}` }; }
      const permissionMode = body.permission_mode ?? settings.permissionMode;
      const id = makeSessionId();
      const session = new ChatSession({
        cwd, permissionMode, resume: body.resume, model: body.model,
      });
      const entry: SessionEntry = { session, buffer: new EventBuffer(), writers: new Set() };
      sessions.set(id, entry);
      consumeSdk(id, entry).catch(() => {});
      return {
        session_id: id,
        cwd,
        permission_mode: permissionMode,
        resumed: body.resume ?? null,
      };
    },
  );

  app.get<{ Params: { id: string }; Querystring: { lastEventId?: string } }>(
    '/chat/:id/events',
    (req, reply) => {
      const { id } = req.params;
      const entry = sessions.get(id);
      if (!entry) { reply.code(404); return reply.send({ error: 'session not found' }); }
      cancelGrace(entry);

      const lastIdHeader = (req.headers['last-event-id'] as string | undefined) ?? req.query.lastEventId;
      const lastId = lastIdHeader ? parseInt(lastIdHeader, 10) : 0;
      if (lastId > 0) {
        const probe = entry.buffer.since(lastId);
        if (probe === null) { reply.code(412); return reply.send({ error: 'event gap, please reload' }); }
      }

      reply.raw.setHeader('Content-Type', 'text/event-stream');
      reply.raw.setHeader('Cache-Control', 'no-cache');
      reply.raw.setHeader('Connection', 'keep-alive');
      reply.raw.flushHeaders();

      const writer = {
        write: (s: string) => reply.raw.write(s),
        end: () => reply.raw.end(),
      };
      entry.writers.add(writer);

      if (lastId > 0) {
        const replay = entry.buffer.since(lastId) ?? [];
        for (const e of replay) {
          writer.write(`id: ${e.id}\nevent: ${e.type}\ndata: ${JSON.stringify(e.data)}\n\n`);
        }
      }

      const heartbeat = setInterval(() => {
        try { writer.write(`: heartbeat\n\n`); } catch { /* */ }
      }, HEARTBEAT_MS);

      req.raw.on('close', () => {
        clearInterval(heartbeat);
        entry.writers.delete(writer);
        if (entry.writers.size === 0) {
          startGrace(id, entry);
        }
      });

      return reply;  // hijacked stream; don't auto-end
    },
  );

  app.post<{ Params: { id: string }; Body: { text: string } }>(
    '/chat/:id/message',
    async (req, reply) => {
      const entry = sessions.get(req.params.id);
      if (!entry) { reply.code(404); return { error: 'session not found' }; }
      entry.session.pushUserMessage(req.body.text);
      return { ok: true };
    },
  );

  app.post<{ Params: { id: string } }>('/chat/:id/interrupt', async (req, reply) => {
    const entry = sessions.get(req.params.id);
    if (!entry) { reply.code(404); return { error: 'session not found' }; }
    await entry.session.interrupt();
    return { ok: true };
  });

  app.post<{ Params: { id: string }; Body: { model: string } }>(
    '/chat/:id/set-model',
    async (req, reply) => {
      const entry = sessions.get(req.params.id);
      if (!entry) { reply.code(404); return { error: 'session not found' }; }
      await entry.session.setModel(req.body.model);
      return { ok: true };
    },
  );

  app.post<{ Params: { id: string }; Body: { mode: PermissionMode } }>(
    '/chat/:id/set-permission-mode',
    async (req, reply) => {
      const entry = sessions.get(req.params.id);
      if (!entry) { reply.code(404); return { error: 'session not found' }; }
      await entry.session.setPermissionMode(req.body.mode);
      return { ok: true };
    },
  );

  app.delete<{ Params: { id: string } }>('/chat/:id', async (req) => {
    closeSession(req.params.id);
    return { ok: true };
  });
}

// Exported only for AskUserQuestion wiring in later tasks to access registry/session.
export function getSessionEntry(id: string): SessionEntry | undefined {
  return sessions.get(id);
}
```

⚠️ 注意：`answerQuestion` 路由暂时不写 —— 留给 Task 8 加（那时 ChatSession 才有 `answerQuestion()` 方法）。

### Step 2b.5: 在 index.ts 注册 chat-rest（保留 ws-chat 双栈）

- [ ] Modify `server/src/index.ts`：

顶部 import 加：
```ts
import { registerChatRest } from './chat-rest.js';
```

在 `await registerSessionsApi(app);` 这行后面加：
```ts
await registerChatRest(app);
```

`ws-chat.ts` 的注册（`app.get('/ws/session', { websocket: true }, ...)`) **暂时不删** —— Task 2c 末尾再删。

### Step 2b.6: typecheck + test

- [ ] Run:

```bash
pnpm typecheck && pnpm test
```

Expected: 无 error；13 测试 PASS。

### Step 2b.7: curl smoke

- [ ] 启 server `pnpm dev`，新 terminal：

```bash
# 替换 <CWD> 为你 config 里 whitelisted 的项目
START=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"cwd":"<CWD>"}' http://localhost:8787/chat/start)
echo $START
SID=$(echo $START | jq -r .session_id)
echo "session: $SID"

# 后台开 SSE 流
curl -s --no-buffer "http://localhost:8787/chat/$SID/events" &
SSE_PID=$!
sleep 1

# 发一条消息
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"hello, say hi back"}' \
  "http://localhost:8787/chat/$SID/message"

# 观察 stdout 应该有 SSE event stream 滚动出来
sleep 30

# 清理
kill $SSE_PID
curl -X DELETE "http://localhost:8787/chat/$SID"
```

Expected: SSE 流里看到 `id: 1`, `event: assistant`, `data: {...}` 这种格式的事件，包含 Claude 的回复内容。

### Step 2b.8: Commit

- [ ] Run:

```bash
git add server/src/event-buffer.ts server/src/__tests__/event-buffer.test.ts server/src/chat-rest.ts server/src/index.ts
git commit -m "feat(server): chat REST + SSE transport with Last-Event-ID resume"
```

---

## Task 2c: §5 Client — 切到 SSE + REST（删 WS chat）

**目标**：客户端从 WebSocket 切到 SSE + REST。Task 2c 末尾删除 server 的 `/ws/session` 注册和 `ws-chat.ts`。

**Files:**
- Create: `app/lib/api/sse_client.dart`
- Create: `app/lib/api/chat_api.dart`
- Modify: `app/lib/screens/tabs/chat_tab.dart`（_ChatTabState 大改）
- Modify: `server/src/index.ts`（删 ws-chat 注册）
- Delete: `server/src/ws-chat.ts`（移除文件）

### Step 2c.1: 写 sse_client.dart

- [ ] Create `app/lib/api/sse_client.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class SseEvent {
  final String? id;
  final String type;
  final String data;
  SseEvent({this.id, required this.type, required this.data});
}

/// 轻量 SSE 客户端：解析 wire format、维护 Last-Event-ID、自动指数退避重连。
class SseClient {
  final Uri url;
  final Map<String, String> headers;
  String? _lastEventId;
  http.Client? _httpClient;
  StreamSubscription<List<int>>? _sub;
  final _events = StreamController<SseEvent>.broadcast();
  bool _closed = false;
  int _backoffMs = 1000;
  static const _maxBackoffMs = 30000;

  SseClient({required this.url, this.headers = const {}});

  Stream<SseEvent> get events => _events.stream;

  /// 进入持续重连循环。close() 之前不会自然返回。
  Future<void> connect() async {
    while (!_closed) {
      try {
        await _connectOnce();
        if (_closed) return;
      } catch (e) {
        _events.add(SseEvent(type: '__client_error', data: e.toString()));
      }
      if (_closed) return;
      await Future.delayed(Duration(milliseconds: _backoffMs));
      _backoffMs = (_backoffMs * 2).clamp(1000, _maxBackoffMs);
    }
  }

  Future<void> _connectOnce() async {
    _httpClient = http.Client();
    final request = http.Request('GET', url);
    request.headers.addAll({
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      ...headers,
    });
    if (_lastEventId != null) {
      request.headers['Last-Event-ID'] = _lastEventId!;
    }
    final response = await _httpClient!.send(request);
    if (response.statusCode == 412) {
      _events.add(SseEvent(type: '__gap', data: 'event gap, reload required'));
      _closed = true;
      return;
    }
    if (response.statusCode != 200) {
      throw Exception('SSE HTTP ${response.statusCode}');
    }
    _backoffMs = 1000;

    final buffer = StringBuffer();
    final completer = Completer<void>();
    _sub = response.stream.listen(
      (chunk) {
        buffer.write(utf8.decode(chunk, allowMalformed: true));
        _drainBuffer(buffer);
      },
      onDone: () => completer.complete(),
      onError: (e) => completer.completeError(e),
      cancelOnError: true,
    );
    await completer.future;
  }

  void _drainBuffer(StringBuffer buffer) {
    final str = buffer.toString();
    int sep;
    int startIdx = 0;
    while ((sep = str.indexOf('\n\n', startIdx)) >= 0) {
      final block = str.substring(startIdx, sep);
      _parseEvent(block);
      startIdx = sep + 2;
    }
    final remaining = str.substring(startIdx);
    buffer.clear();
    buffer.write(remaining);
  }

  void _parseEvent(String block) {
    String? id;
    String type = 'message';
    final dataLines = <String>[];
    for (final line in block.split('\n')) {
      if (line.startsWith(':')) continue; // SSE comment
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final field = line.substring(0, colon);
      var value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'id':
          id = value;
          break;
        case 'event':
          type = value;
          break;
        case 'data':
          dataLines.add(value);
          break;
      }
    }
    if (id != null) _lastEventId = id;
    _events.add(SseEvent(id: id, type: type, data: dataLines.join('\n')));
  }

  Future<void> close() async {
    _closed = true;
    await _sub?.cancel();
    _httpClient?.close();
    await _events.close();
  }
}
```

### Step 2c.2: 写 chat_api.dart

- [ ] Create `app/lib/api/chat_api.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

class ChatStartResponse {
  final String sessionId;
  final String cwd;
  final String permissionMode;
  final String? resumed;
  ChatStartResponse({
    required this.sessionId,
    required this.cwd,
    required this.permissionMode,
    this.resumed,
  });
  factory ChatStartResponse.fromJson(Map<String, dynamic> j) => ChatStartResponse(
        sessionId: j['session_id'] as String,
        cwd: j['cwd'] as String,
        permissionMode: j['permission_mode'] as String,
        resumed: j['resumed'] as String?,
      );
}

class ChatApiException implements Exception {
  final int status;
  final String message;
  ChatApiException(this.status, this.message);
  @override
  String toString() => 'ChatApiException($status): $message';
}

class ChatApi {
  final String httpBase;
  ChatApi(this.httpBase);

  Future<ChatStartResponse> start({
    required String cwd,
    String? permissionMode,
    String? resume,
    String? model,
  }) async {
    final resp = await http.post(
      Uri.parse('$httpBase/chat/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'cwd': cwd,
        if (permissionMode != null) 'permission_mode': permissionMode,
        if (resume != null) 'resume': resume,
        if (model != null) 'model': model,
      }),
    );
    if (resp.statusCode != 200) {
      throw ChatApiException(resp.statusCode, resp.body);
    }
    return ChatStartResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> sendMessage(String sessionId, String text) async {
    final resp = await http.post(
      Uri.parse('$httpBase/chat/$sessionId/message'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    if (resp.statusCode != 200) {
      throw ChatApiException(resp.statusCode, resp.body);
    }
  }

  Future<void> answerQuestion(
    String sessionId,
    String toolUseId,
    Map<String, String> answers,
    Map<String, Map<String, String>>? annotations,
  ) async {
    final resp = await http.post(
      Uri.parse('$httpBase/chat/$sessionId/answer-question'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tool_use_id': toolUseId,
        'answers': answers,
        if (annotations != null) 'annotations': annotations,
      }),
    );
    if (resp.statusCode != 200) {
      throw ChatApiException(resp.statusCode, resp.body);
    }
  }

  Future<void> interrupt(String sessionId) async {
    await http.post(Uri.parse('$httpBase/chat/$sessionId/interrupt'));
  }

  Future<void> setModel(String sessionId, String model) async {
    await http.post(
      Uri.parse('$httpBase/chat/$sessionId/set-model'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'model': model}),
    );
  }

  Future<void> setPermissionMode(String sessionId, String mode) async {
    await http.post(
      Uri.parse('$httpBase/chat/$sessionId/set-permission-mode'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'mode': mode}),
    );
  }

  Future<void> close(String sessionId) async {
    await http.delete(Uri.parse('$httpBase/chat/$sessionId'));
  }
}
```

### Step 2c.3: 改造 chat_tab.dart 的 _ChatTabState

这一步是 Task 2c 主体。把 WebSocket 相关代码（`_channel`, `_openSessionWebSocket`, `_onData`, `_onError`, `_onDone`）替换为 `ChatApi` + `SseClient`。

- [ ] 顶部 import 调整：

删掉：
```dart
import 'package:web_socket_channel/web_socket_channel.dart';
```

加：
```dart
import '../../api/chat_api.dart';
import '../../api/sse_client.dart';
```

- [ ] 替换 `_ChatTabState` 中的字段：

```dart
// 删掉：
WebSocketChannel? _channel;

// 加：
ChatApi? _chatApi;
SseClient? _sseClient;
String? _sessionId;
```

- [ ] 替换 `_openSessionWebSocket` 方法为 `_openSseSession`：

```dart
Future<void> _openSseSession(String httpBase, CurrentSession session) async {
  // History first
  if (session.resumeId != null) {
    _loadHistory(httpBase, session.cwd, session.resumeId!);
  }

  _chatApi = ChatApi(httpBase);
  final model = ref.read(currentModelProvider);
  final permMode = ref.read(permissionModeProvider);

  try {
    final start = await _chatApi!.start(
      cwd: session.cwd,
      permissionMode: _permModeToString(permMode),
      resume: session.resumeId,
      model: model.id,
    );
    _sessionId = start.sessionId;
    if (!mounted) return;
    setState(() {
      _connected = true;
      _attempting = false;
    });
  } catch (e) {
    _attempting = false;
    if (!mounted) return;
    setState(() => _error = '$e');
    return;
  }

  final sseUrl = Uri.parse('$httpBase/chat/$_sessionId/events');
  _sseClient = SseClient(url: sseUrl);
  _sseClient!.events.listen(_onSseEvent);
  // 不 await — 在后台跑重连循环
  unawaited(_sseClient!.connect());
}
```

- [ ] 加 `_onSseEvent`，把原来 `_onData` 的逻辑放进来（去掉 jsonDecode 那一层；data 已经是字符串，但需要 jsonDecode）：

```dart
void _onSseEvent(SseEvent ev) {
  if (ev.type.startsWith('__')) {
    // __client_error / __gap：内部状态事件
    if (ev.type == '__gap') {
      // 缓冲 gap：刷历史
      setState(() => _error = 'event gap, reloading…');
      _channel?.sink.close();
      _channel = null;
      _attemptedKey = null;
      // 触发重连：_ensureConnected 会重新走一遍
    }
    return;
  }
  try {
    final json = jsonDecode(ev.data) as Map<String, dynamic>;
    _handleWireMessage(json);
  } catch (_) { /* malformed event, skip */ }
}
```

- [ ] 抽取原 `_onData` 内除 jsonDecode 外的所有逻辑为 `_handleWireMessage(Map<String, dynamic> json)`，签名调整：

原 `_onData(dynamic raw)` 是 `final json = jsonDecode(raw as String) as Map<String, dynamic>;` 然后用 json 做一堆 switch。把那段全部移到 `_handleWireMessage(json)`，删掉 jsonDecode 那行。`_onError` / `_onDone` 可以删除。

- [ ] 修改 `_ensureConnected` 调用点：

```dart
// 把 _openSessionWebSocket(config.wsBase, session) 换成：
_openSseSession(config.httpBase, session);
```

注意：`_resumeWithHolderCheck` 内部最后也是调 `_openSessionWebSocket`，改为 `_openSseSession`。`wsBase` 参数可以删除（不再需要）。

- [ ] 改 `_submit()`（发消息）：

```dart
// 把原来的：
_channel!.sink.add(jsonEncode({'type': 'user_message', 'text': text}));

// 换成：
if (_sessionId != null) {
  unawaited(_chatApi!.sendMessage(_sessionId!, text));
}
```

- [ ] 改 `_onStop()`、`_onSwitchModel(...)`、`_onSwitchPermissionMode(...)` 同理 —— 把 `_channel!.sink.add(jsonEncode(...))` 换成对应的 `_chatApi!.interrupt(...)` / `.setModel(...)` / `.setPermissionMode(...)`。具体实现：

```dart
void _onStop() {
  if (_sessionId != null) unawaited(_chatApi!.interrupt(_sessionId!));
}

void _onSwitchModel(ModelOption m) {
  ref.read(currentModelProvider.notifier).state = m;
  if (_sessionId != null) unawaited(_chatApi!.setModel(_sessionId!, m.id));
}

void _onSwitchPermissionMode(CcPermissionMode mode) {
  ref.read(permissionModeProvider.notifier).state = mode;
  if (_sessionId != null) unawaited(_chatApi!.setPermissionMode(_sessionId!, _permModeToString(mode)));
}
```

- [ ] 加 enum 字符串转换的小工具：

```dart
String _permModeToString(CcPermissionMode m) {
  switch (m) {
    case CcPermissionMode.defaultMode: return 'default';
    case CcPermissionMode.acceptEdits: return 'acceptEdits';
    case CcPermissionMode.plan: return 'plan';
    case CcPermissionMode.bypassPermissions: return 'bypassPermissions';
  }
}
```

- [ ] 改 `dispose()`：

```dart
@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  _thoughtForTimer?.cancel();
  // 关闭 SSE
  _sseClient?.close();
  // 主动通知 server 关闭 session（best-effort，失败也无所谓）
  if (_sessionId != null && _chatApi != null) {
    unawaited(_chatApi!.close(_sessionId!));
  }
  _textController.dispose();
  _scrollController.removeListener(_onScroll);
  _scrollController.dispose();
  super.dispose();
}
```

### Step 2c.4: flutter analyze

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion/app
flutter analyze lib/api/sse_client.dart lib/api/chat_api.dart lib/screens/tabs/chat_tab.dart
```

Expected: 无 error。可能有"未使用的 import"，按 IDE 提示清理。

### Step 2c.5: 手动 smoke

- [ ] 启 server + app
- [ ] 打开 chat tab：
  - 期望：能正常发消息，能看到 Claude 流式回复
  - 期望：interrupt 按钮能停下生成
  - 期望：切模型、切权限模式 OK
- [ ] 测试断线重连：
  - 在 app 流式回复进行中飞行模式打开 10s 再关闭
  - 期望：流暂停后能续接，不丢中间内容（30s 内 buffer 续传）
- [ ] 测试 grace 超时：
  - 关 app 30+ 秒 → 重开 → server 端 session 已 GC
  - 期望：重新触发 _ensureConnected 走新会话

### Step 2c.6: 删除 ws-chat.ts + 注册

- [ ] Modify `server/src/index.ts`，删除：

```ts
// 删除这两行：
import { handleChatSocket } from './ws-chat.js';
// ...
app.get('/ws/session', { websocket: true }, (socket, req) => {
  handleChatSocket(socket, req);
});
```

- [ ] 删除文件：

```bash
cd /Users/airoucat/workspace/shulex/claude-companion
rm server/src/ws-chat.ts
```

⚠️ 注意：删文件是有损操作。本步骤之前 git 已有 ws-chat.ts 的历史，rm 之后追加 commit 即可，不需要特殊保护。

### Step 2c.7: typecheck 确认 server 还能编译

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion/server
pnpm typecheck && pnpm test
```

Expected: 无 error；13 测试 PASS。

### Step 2c.8: Commit

- [ ] Run:

```bash
git add app/lib/api/sse_client.dart app/lib/api/chat_api.dart app/lib/screens/tabs/chat_tab.dart server/src/index.ts
git rm server/src/ws-chat.ts
git commit -m "feat(chat): migrate transport to SSE + REST (delete ws-chat)"
```

---

## Task 3: §2 Server 端 `/upload` 端点

**目标**：把附件接到 server 的 cwd 下。

**Files:**
- Modify: `server/package.json`
- Create: `server/src/upload.ts`
- Modify: `server/src/index.ts:1-20, 167-170`

### Step 3.1: 装 multipart 插件

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion/server
pnpm add @fastify/multipart
```

Expected: `package.json` 加 `"@fastify/multipart": "^9.x.x"`（具体版本号 pnpm 决定）。

### Step 3.2: 写 upload.ts

- [ ] Create `server/src/upload.ts`:

```ts
import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { mkdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

import { isPathAllowed } from './config.js';

const MAX_FILE_BYTES = 25 * 1024 * 1024; // 25 MB

/**
 * Sanitize a filename so it stays a single path segment.
 * - drop path separators
 * - keep ASCII letters / digits / . - _ ; replace others with _
 * - collapse repeats; trim leading dots (no hidden files)
 */
function sanitize(name: string): string {
  const base = name.replace(/[/\\]/g, '');
  let out = '';
  for (const ch of base) {
    out += /[A-Za-z0-9._\-]/.test(ch) ? ch : '_';
  }
  out = out.replace(/_+/g, '_').replace(/^\.+/, '');
  return out || 'file';
}

function timestamp(): string {
  const d = new Date();
  const pad = (n: number, w = 2) => String(n).padStart(w, '0');
  return (
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-` +
    `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}-` +
    `${pad(d.getMilliseconds(), 3)}`
  );
}

export async function registerUpload(app: FastifyInstance): Promise<void> {
  app.post('/upload', async (req: FastifyRequest, reply: FastifyReply) => {
    const cwd = (req.query as { cwd?: string }).cwd;
    if (!cwd) {
      reply.code(400);
      return { error: 'cwd required' };
    }
    const abs = resolve(cwd);
    if (!isPathAllowed(abs)) {
      reply.code(403);
      return { error: 'cwd not allowed' };
    }

    const part = await req.file({ limits: { fileSize: MAX_FILE_BYTES } });
    if (!part) {
      reply.code(400);
      return { error: 'no file' };
    }

    const buf = await part.toBuffer();
    if (part.file.truncated) {
      reply.code(413);
      return { error: `file exceeds ${MAX_FILE_BYTES} bytes` };
    }

    const dir = join(abs, '.claude', 'attachments');
    await mkdir(dir, { recursive: true });
    const filename = `${timestamp()}-${sanitize(part.filename)}`;
    const dest = join(dir, filename);
    await writeFile(dest, buf);

    return { path: dest, size: buf.length };
  });
}
```

### Step 3.3: 注册到 index.ts

- [ ] Modify `server/src/index.ts`：

在文件顶部 import 区域加：
```ts
import multipart from '@fastify/multipart';
import { registerUpload } from './upload.js';
```

在 `await app.register(websocketPlugin);` 这行之后（约 23 行）加：
```ts
await app.register(multipart, { limits: { fileSize: 25 * 1024 * 1024 } });
```

在 `await registerSessionsApi(app);` 这行之后（约 168 行）加：
```ts
await registerUpload(app);
```

### Step 3.4: 跑 typecheck

- [ ] Run:

```bash
pnpm typecheck
```

Expected: 无 error。

### Step 3.5: 手动 smoke（启动 server + curl）

- [ ] 启 server（独立 terminal）：

```bash
pnpm dev
```

等到 `Claude Companion server v0.2.0 on http://...`。

- [ ] 准备一个测试文件 + 一个 `cwd`（需要是 config 里 whitelisted 的项目）：

```bash
# 用你配置文件里某个 project 路径替换 <CWD>
echo "hello attachment" > /tmp/test.txt
curl -F "file=@/tmp/test.txt" "http://localhost:8787/upload?cwd=$(echo <CWD> | jq -sRr @uri)"
```

Expected: 返回 `{"path":"<CWD>/.claude/attachments/2026...-test.txt","size":16}`。
检查文件确实落地：`ls -la <CWD>/.claude/attachments/`。

- [ ] 再验证拒绝路径：

```bash
curl -F "file=@/tmp/test.txt" "http://localhost:8787/upload?cwd=/tmp"
```

Expected：HTTP 403，`{"error":"cwd not allowed"}`（除非你恰好 whitelist 了 `/tmp`）。

- [ ] 验证超大文件被拒：

```bash
dd if=/dev/zero of=/tmp/big.bin bs=1M count=26
curl -F "file=@/tmp/big.bin" "http://localhost:8787/upload?cwd=<CWD>"
```

Expected: HTTP 413 + `{"error":"file exceeds ..."}`。

### Step 3.6: Commit

- [ ] Run:

```bash
git add server/package.json server/pnpm-lock.yaml server/src/upload.ts server/src/index.ts
# 注意如果 pnpm-lock.yaml 在仓库根目录就 git add 根目录的 lock
git commit -m "feat(server): POST /upload endpoint for chat attachments"
```

---

## Task 4: §2 Client 端附件上传集成

**目标**：composer 加 `+` 按钮 + 上传 chip 行 + 发送时拼接路径。

**Files:**
- Modify: `app/pubspec.yaml`
- Create: `app/lib/api/upload_api.dart`
- Modify: `app/lib/screens/tabs/chat_tab.dart` (`_Composer` + 新增 `_AttachmentChip` + `_AttachmentState`)

### Step 4.1: 加 file_picker 依赖

- [ ] Modify `app/pubspec.yaml`，在 `dependencies:` 下加：

```yaml
  file_picker: ^8.0.0
```

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion/app
flutter pub get
```

Expected: 无 error，`pubspec.lock` 更新。

### Step 4.2: 写 upload_api.dart

- [ ] Create `app/lib/api/upload_api.dart`:

```dart
import 'dart:io';

import 'package:http/http.dart' as http;
import 'dart:convert';

class UploadedFile {
  final String path;
  final int size;
  UploadedFile({required this.path, required this.size});

  factory UploadedFile.fromJson(Map<String, dynamic> json) =>
      UploadedFile(path: json['path'] as String, size: json['size'] as int);
}

class UploadException implements Exception {
  final int status;
  final String message;
  UploadException(this.status, this.message);
  @override
  String toString() => 'UploadException($status): $message';
}

class UploadApi {
  final String httpBase;
  UploadApi(this.httpBase);

  Future<UploadedFile> upload(File file, String cwd) async {
    final uri = Uri.parse('$httpBase/upload').replace(queryParameters: {'cwd': cwd});
    final req = http.MultipartRequest('POST', uri);
    req.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return UploadedFile.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    String msg = resp.body;
    try {
      msg = (jsonDecode(resp.body) as Map<String, dynamic>)['error']?.toString() ?? resp.body;
    } catch (_) {}
    throw UploadException(resp.statusCode, msg);
  }
}
```

### Step 4.3: 在 chat_tab.dart 加附件状态模型

- [ ] 在 `chat_tab.dart` 顶部（其它类定义之间，建议放在 `_HistoryPage` 后面）加：

```dart
enum _AttachmentStatus { uploading, ready, failed }

class _AttachmentState {
  final String localName;
  final String localPath;
  String? remotePath;
  String? errorMsg;
  _AttachmentStatus status;
  _AttachmentState({
    required this.localName,
    required this.localPath,
    required this.status,
    this.remotePath,
    this.errorMsg,
  });
}
```

### Step 4.4: 在 _ChatTabState 加附件管理逻辑

- [ ] 在 `_ChatTabState` 类里（与 `_pending` 同区域）加状态：

```dart
final List<_AttachmentState> _attachments = [];
```

- [ ] 加方法（放在类的末尾、`dispose()` 之前任意位置都行）：

```dart
Future<void> _pickAndUploadAttachments() async {
  // 延迟 import，避免顶部加 file_picker import 用不上时也被分析。
  // 但 Dart 没法做 lazy import，所以还是顶部加：
  //   import 'package:file_picker/file_picker.dart';
  // —— 这一步在 step 4.5 做。
  final result = await FilePicker.platform.pickFiles(allowMultiple: true);
  if (result == null) return;
  final session = ref.read(currentSessionProvider);
  if (session == null) return;
  final config = ref.read(activeConnectionProvider);
  if (config == null) return;
  final api = UploadApi(config.httpBase);
  for (final pickedFile in result.files) {
    final path = pickedFile.path;
    if (path == null) continue;
    final state = _AttachmentState(
      localName: pickedFile.name,
      localPath: path,
      status: _AttachmentStatus.uploading,
    );
    setState(() => _attachments.add(state));
    // 不 await：并行上传
    unawaited(_uploadOne(api, state, session.cwd));
  }
}

Future<void> _uploadOne(UploadApi api, _AttachmentState state, String cwd) async {
  try {
    final result = await api.upload(File(state.localPath), cwd);
    if (!mounted) return;
    setState(() {
      state.remotePath = result.path;
      state.status = _AttachmentStatus.ready;
    });
  } catch (e) {
    if (!mounted) return;
    setState(() {
      state.errorMsg = e.toString();
      state.status = _AttachmentStatus.failed;
    });
  }
}

void _removeAttachment(_AttachmentState a) {
  setState(() => _attachments.remove(a));
}

Future<void> _retryAttachment(_AttachmentState a) async {
  final session = ref.read(currentSessionProvider);
  final config = ref.read(activeConnectionProvider);
  if (session == null || config == null) return;
  setState(() {
    a.status = _AttachmentStatus.uploading;
    a.errorMsg = null;
  });
  await _uploadOne(UploadApi(config.httpBase), a, session.cwd);
}

bool get _attachmentsAllReady =>
    _attachments.every((a) => a.status == _AttachmentStatus.ready);
```

### Step 4.5: 顶部加 imports

- [ ] 在 `chat_tab.dart` 顶部 import 区追加：

```dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../api/upload_api.dart';
```

（如果已有 `dart:io` / `dart:async` 则跳过对应行；`unawaited` 在 `dart:async`）

### Step 4.6: 改 _submit 把附件路径拼进文本

⚠️ 此时 chat_tab.dart 已经在 Task 2c 中切到了 `_chatApi.sendMessage(...)`，所以这里改的是 `_chatApi.sendMessage` 之前的 text 组装部分。

- [ ] 找到 `chat_tab.dart` 里的 `_submit()`（grep `void _submit`）方法，在 `_chatApi!.sendMessage(_sessionId!, ...)` 之前组装附件路径：

```dart
final raw = _textController.text.trim();
final attachLines = _attachments
    .where((a) => a.status == _AttachmentStatus.ready && a.remotePath != null)
    .map((a) => '`${a.remotePath!}`')
    .toList();
final text = attachLines.isEmpty
    ? raw
    : '$raw\n\n附件：\n${attachLines.join('\n')}';
if (text.isEmpty) return;
// 后续走 _chatApi.sendMessage(_sessionId!, text)（已由 Task 2c 替换）
```

发送成功后清空附件（`_textController.clear();` 那行附近加）：
```dart
setState(() => _attachments.clear());
```

发送禁用条件加上"附件全 ready"，把发送按钮调用点的 `canSend` 表达式改为：
```dart
final canSend = _connected && !_busy && _attachmentsAllReady;
```

（注：当前代码 `canSend` 在 `_Composer.build()` 内由 `connected && !busy` 决定；改这处后还要把 `_attachmentsAllReady` 通过参数传给 `_Composer`）

### Step 4.7: 改 _Composer 接收附件状态 + 加 chip 行 + 加 `+` 按钮

- [ ] 改 `_Composer` 构造器，新增参数：

```dart
class _Composer extends ConsumerWidget {
  final TextEditingController controller;
  final bool connected;
  final bool busy;
  final List<_AttachmentState> attachments;
  final bool attachmentsAllReady;
  final VoidCallback onPickAttachment;
  final void Function(_AttachmentState) onRemoveAttachment;
  final void Function(_AttachmentState) onRetryAttachment;
  final VoidCallback onSubmit;
  final VoidCallback onStop;
  final void Function(ModelOption) onSwitchModel;
  final void Function(CcPermissionMode) onSwitchPermissionMode;
  const _Composer({
    required this.controller,
    required this.connected,
    required this.busy,
    required this.attachments,
    required this.attachmentsAllReady,
    required this.onPickAttachment,
    required this.onRemoveAttachment,
    required this.onRetryAttachment,
    required this.onSubmit,
    required this.onStop,
    required this.onSwitchModel,
    required this.onSwitchPermissionMode,
  });
  // ...
}
```

- [ ] 在 `_Composer.build()` 内，把现有的 `Column(children: [...])` 内容调整为三段（附件行 / 文本框行 / 工具栏行）：

```dart
return SafeArea(
  top: false,
  child: Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    child: Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border, width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 附件 chip 行（非空时显示）
          if (attachments.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in attachments)
                    _AttachmentChip(
                      state: a,
                      onRemove: () => onRemoveAttachment(a),
                      onRetry: () => onRetryAttachment(a),
                    ),
                ],
              ),
            ),
          ],
          // 输入框 + 发送按钮
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 2,
                  maxLines: 6,
                  enabled: connected,
                  cursorColor: t.accent,
                  style: TextStyle(fontSize: 14, color: t.text, height: 1.4),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    hintText: connected ? 'Ask Claude…' : 'Connecting…',
                    hintStyle: TextStyle(color: t.textDim, fontSize: 14),
                  ),
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                ),
              ),
              const SizedBox(width: 8),
              _SendOrStopButton(
                busy: busy,
                canSend: connected && !busy && attachmentsAllReady,
                onSubmit: onSubmit,
                onStop: onStop,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 工具栏
          Row(
            children: [
              // [+] 上传按钮
              GestureDetector(
                onTap: connected ? onPickAttachment : null,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: connected ? t.textMuted : t.textDim,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _PermissionModePicker(
                current: ref.watch(permissionModeProvider),
                onPick: onSwitchPermissionMode,
              ),
              _ModelPicker(current: model, onPick: onSwitchModel),
              const Spacer(),
            ],
          ),
        ],
      ),
    ),
  ),
);
```

### Step 4.8: 写 _AttachmentChip 组件

- [ ] 在 `chat_tab.dart` 文件末尾（或紧跟 `_SendOrStopButton` 后）新增：

```dart
class _AttachmentChip extends StatelessWidget {
  final _AttachmentState state;
  final VoidCallback onRemove;
  final VoidCallback onRetry;
  const _AttachmentChip({
    required this.state,
    required this.onRemove,
    required this.onRetry,
  });

  IconData _iconForName(String name) {
    final lower = name.toLowerCase();
    if (RegExp(r'\.(png|jpg|jpeg|webp|heic|heif|gif|bmp)$').hasMatch(lower)) {
      return Icons.image_outlined;
    }
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (RegExp(r'\.(ts|tsx|js|jsx|py|dart|go|rs|java|c|cpp|h|hpp|json|yaml|yml|md|sh)$').hasMatch(lower)) {
      return Icons.code;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final failed = state.status == _AttachmentStatus.failed;
    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: BoxDecoration(
        color: t.surfaceHi,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: failed ? t.error.withValues(alpha: 0.5) : t.border,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconForName(state.localName), size: 14, color: t.textMuted),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              state.localName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: t.text),
            ),
          ),
          const SizedBox(width: 6),
          if (state.status == _AttachmentStatus.uploading)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          else if (failed)
            GestureDetector(
              onTap: onRetry,
              child: Icon(Icons.error_outline, size: 14, color: t.error),
            )
          else
            GestureDetector(
              onTap: onRemove,
              child: Icon(Icons.close_rounded, size: 14, color: t.textMuted),
            ),
        ],
      ),
    );
  }
}
```

### Step 4.9: 把新参数传给 _Composer 的调用点

- [ ] 找到 `_ChatTabState` 里调用 `_Composer(...)` 的地方（在 `build()` 里），改成：

```dart
_Composer(
  controller: _textController,
  connected: _connected,
  busy: _busy,
  attachments: _attachments,
  attachmentsAllReady: _attachmentsAllReady,
  onPickAttachment: _pickAndUploadAttachments,
  onRemoveAttachment: _removeAttachment,
  onRetryAttachment: _retryAttachment,
  onSubmit: _submit,
  onStop: _onStop,
  onSwitchModel: _onSwitchModel,
  onSwitchPermissionMode: _onSwitchPermissionMode,
)
```

### Step 4.10: 跑 flutter analyze

- [ ] Run:

```bash
flutter analyze lib/screens/tabs/chat_tab.dart lib/api/upload_api.dart
```

Expected: 无 error。

### Step 4.11: 手动 smoke

- [ ] 启 server + app（如果还没起）：
  - server: `cd server && pnpm dev`
  - app: `cd app && flutter run`
- [ ] 打开 chat tab，点 `+`，选 1 个图片 + 1 个 PDF
  - 期望：两个 chip 都先 spinner，然后变成 ×
  - 期望：发送按钮在所有 chip ready 之前禁用
- [ ] 输入"看看这两个文件" + 按发送
  - 期望：消息发出去，文本里看到 `附件：` + 两个路径
  - 期望：Claude 收到后可以 `Read` 文件
- [ ] 模拟失败：关掉 server，再点 + 上传
  - 期望：chip 变红，tap 重试

### Step 4.12: Commit

- [ ] Run:

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/api/upload_api.dart app/lib/screens/tabs/chat_tab.dart
git commit -m "feat(composer): attachment upload with path injection"
```

---

## Task 5: §4 协议层 — `AnswerQuestionRequest` REST 类型

**目标**：在 Task 2b/2c 完成 SSE 迁移后，`answer_question` 不再是 WS 消息变体，而是 `POST /chat/<id>/answer-question` 的请求 body 类型。这一 task 同时清理 `ChatClientMessage` union 残留（如果 Task 2b/2c 没顺手清的话）。

**Files:**
- Modify: `packages/shared/src/protocol.ts`

### Step 5.1: 添加 AnswerQuestionRequest 类型

- [ ] Modify `packages/shared/src/protocol.ts`，在文件靠下位置（紧跟 §5 SSE 已添加的其他 REST 类型，例如 `ChatStartRequest`、`SendMessageRequest` 之后）加：

```ts
/** POST /chat/<id>/answer-question 请求 body */
export interface AnswerQuestionRequest {
  tool_use_id: string;
  answers: Record<string, string>;
  annotations?: Record<string, { preview?: string; notes?: string }>;
}
```

### Step 5.2: 确认 ChatClientMessage 已删

Task 2b/2c 应该已经把 `ChatClientMessage` union 删干净。如果还残留，删掉。

- [ ] 检查：

```bash
cd /Users/airoucat/workspace/shulex/claude-companion
grep -n "ChatClientMessage" packages/shared/src/protocol.ts || echo "OK: not found"
```

Expected: `OK: not found`

### Step 5.3: typecheck

- [ ] Run:

```bash
pnpm -r typecheck
```

Expected: 无 error（特别是 server 端引用 `AnswerQuestionRequest` 的地方在 Task 8 才出现，这里只确认类型本身能编译）。

### Step 5.4: Commit

- [ ] Run:

```bash
git add packages/shared/src/protocol.ts
git commit -m "feat(protocol): add AnswerQuestionRequest REST body type"
```

---

## Task 6: §4 Server — AskUserQuestionRegistry + 单元测试

**目标**：纯逻辑类，先写测试。

**Files:**
- Create: `server/src/ask-user-tool.ts`（只先放 Registry 类，工厂在 Task 7 加）
- Create: `server/src/__tests__/ask-user-tool.test.ts`

### Step 6.1: 装 zod 显式依赖

zod 是 SDK 的 peer，但我们自己也用，显式声明：

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion/server
pnpm add zod
```

### Step 6.2: 写测试

- [ ] Create `server/src/__tests__/ask-user-tool.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';
import { AskUserQuestionRegistry } from '../ask-user-tool.js';

describe('AskUserQuestionRegistry', () => {
  it('resolves the registered promise when answer() is called', async () => {
    const r = new AskUserQuestionRegistry();
    const promise = r.register('id1');
    const ok = r.answer('id1', 'hello');
    expect(ok).toBe(true);
    const result = await promise;
    expect(result.content).toEqual([{ type: 'text', text: 'hello' }]);
  });

  it('answer() returns false for unknown tool_use_id', () => {
    const r = new AskUserQuestionRegistry();
    expect(r.answer('nope', 'x')).toBe(false);
  });

  it('rejectAll() rejects all pending promises', async () => {
    const r = new AskUserQuestionRegistry();
    const p1 = r.register('a');
    const p2 = r.register('b');
    r.rejectAll('socket closed');
    await expect(p1).rejects.toThrow('socket closed');
    await expect(p2).rejects.toThrow('socket closed');
  });

  it('answer() after rejectAll() returns false', () => {
    const r = new AskUserQuestionRegistry();
    r.register('a').catch(() => {}); // swallow rejection
    r.rejectAll('x');
    expect(r.answer('a', 'late')).toBe(false);
  });

  it('register times out after the configured ms', async () => {
    vi.useFakeTimers();
    const r = new AskUserQuestionRegistry({ timeoutMs: 1000 });
    const p = r.register('id1').catch((e) => e);
    vi.advanceTimersByTime(1001);
    const err = await p;
    expect(err).toBeInstanceOf(Error);
    expect((err as Error).message).toMatch(/30 minutes|within/i);
    vi.useRealTimers();
  });
});
```

### Step 6.3: 写最小 Registry 实现让测试通过

- [ ] Create `server/src/ask-user-tool.ts`:

```ts
import type { CallToolResult } from '@anthropic-ai/claude-agent-sdk/sdk-tools.js';

type Resolver = (result: CallToolResult) => void;
type Rejecter = (err: Error) => void;

const DEFAULT_TIMEOUT_MS = 30 * 60 * 1000;

export class AskUserQuestionRegistry {
  private pending = new Map<string, { resolve: Resolver; reject: Rejecter; timer: NodeJS.Timeout }>();
  private readonly timeoutMs: number;

  constructor(opts: { timeoutMs?: number } = {}) {
    this.timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  }

  register(toolUseId: string): Promise<CallToolResult> {
    return new Promise<CallToolResult>((resolve, reject) => {
      const timer = setTimeout(() => {
        if (this.pending.has(toolUseId)) {
          this.pending.delete(toolUseId);
          reject(new Error(`User did not answer within ${Math.round(this.timeoutMs / 60000)} minutes`));
        }
      }, this.timeoutMs);
      this.pending.set(toolUseId, { resolve, reject, timer });
    });
  }

  answer(toolUseId: string, formatted: string): boolean {
    const entry = this.pending.get(toolUseId);
    if (!entry) return false;
    clearTimeout(entry.timer);
    this.pending.delete(toolUseId);
    entry.resolve({ content: [{ type: 'text', text: formatted }] });
    return true;
  }

  rejectAll(reason: string): void {
    for (const [, { reject, timer }] of this.pending) {
      clearTimeout(timer);
      reject(new Error(reason));
    }
    this.pending.clear();
  }
}
```

⚠️ 如果 `@anthropic-ai/claude-agent-sdk/sdk-tools.js` 的子路径 export 不可用（取决于 SDK 的 `exports` 字段），fallback：

```ts
// 定义本地 CallToolResult，不 import：
type CallToolResult = { content: Array<{ type: 'text'; text: string }> };
```

### Step 6.4: 跑测试

- [ ] Run:

```bash
pnpm test
```

Expected: 7（serialize）+ 5（registry）= 12 PASS。

### Step 6.5: typecheck

- [ ] Run:

```bash
pnpm typecheck
```

Expected: 无 error。

### Step 6.6: Commit

- [ ] Run:

```bash
git add server/package.json server/pnpm-lock.yaml server/src/ask-user-tool.ts server/src/__tests__/ask-user-tool.test.ts
git commit -m "feat(server): AskUserQuestionRegistry for pending tool calls"
```

---

## Task 7: §4 Server — ask-user-tool MCP 工厂 + Zod schema

**Files:**
- Modify: `server/src/ask-user-tool.ts`（加 `makeAskUserMcpServer()` 工厂）

### Step 7.1: 加 Zod schema + tool 工厂

- [ ] 在 `server/src/ask-user-tool.ts` 末尾追加：

```ts
import { createSdkMcpServer, tool } from '@anthropic-ai/claude-agent-sdk';
import { z } from 'zod';

const optionSchema = z.object({
  label: z.string().describe('The display text for this option that the user will see and select.'),
  description: z.string().describe('Explanation of what this option means.'),
  preview: z.string().optional().describe('Optional preview content rendered when this option is focused. Use for mockups, code snippets, or visual comparisons.'),
});

const questionSchema = z.object({
  question: z.string().describe('The complete question to ask the user. Should be clear, specific, and end with a question mark.'),
  header: z.string().describe('Very short label displayed as a chip/tag (max 12 chars).'),
  options: z.array(optionSchema).min(2).max(4).describe('The available choices for this question. Must have 2-4 options.'),
  multiSelect: z.boolean().default(false).describe('Set to true to allow the user to select multiple options.'),
});

const inputSchema = {
  questions: z.array(questionSchema).min(1).max(4).describe('Questions to ask the user (1-4 questions)'),
};

const TOOL_DESCRIPTION = `Use this tool when you need to ask the user questions during execution. This allows you to:
1. Gather user preferences or requirements
2. Clarify ambiguous instructions
3. Get decisions on implementation choices as you work
4. Offer choices to the user about what direction to take.

Usage notes:
- Users will always be able to select "Other" to provide custom text input
- Use multiSelect: true to allow multiple answers to be selected for a question
- If you recommend a specific option, make that the first option in the list and add "(Recommended)" at the end of the label
`;

export function makeAskUserMcpServer(registry: AskUserQuestionRegistry) {
  return createSdkMcpServer({
    name: 'ask-user-question',
    tools: [
      tool(
        'AskUserQuestion',
        TOOL_DESCRIPTION,
        inputSchema,
        async (_input, extra: unknown) => {
          // extra typed by SDK as MCP server context; tool_use_id at extra.toolUseId
          const toolUseId = (extra as { toolUseId?: string })?.toolUseId;
          if (!toolUseId) {
            throw new Error('No toolUseId in MCP context');
          }
          return registry.register(toolUseId);
        },
      ),
    ],
  });
}

// Format question answers into the cc-style result string the SDK will pass to Claude.
export function formatAnswers(
  questionsAnswered: Record<string, string>,
  annotations?: Record<string, { preview?: string; notes?: string }>,
): string {
  const parts: string[] = [];
  for (const [question, answer] of Object.entries(questionsAnswered)) {
    const seg: string[] = [`Q: ${question}`, `A: ${answer}`];
    const ann = annotations?.[question];
    if (ann?.preview) seg.push(`selected preview:\n${ann.preview}`);
    if (ann?.notes) seg.push(`notes:\n${ann.notes}`);
    parts.push(seg.join('\n'));
  }
  return `User has answered your questions:\n\n${parts.join('\n\n')}\n\nYou can now continue with the user's answers in mind.`;
}
```

### Step 7.2: 给 formatAnswers 加测试

- [ ] 在 `server/src/__tests__/ask-user-tool.test.ts` 末尾追加：

```ts
import { formatAnswers } from '../ask-user-tool.js';

describe('formatAnswers', () => {
  it('formats single question single answer', () => {
    const out = formatAnswers({ 'Which library?': 'date-fns' });
    expect(out).toContain('Q: Which library?');
    expect(out).toContain('A: date-fns');
    expect(out).toContain('User has answered your questions:');
    expect(out).toContain('You can now continue');
  });

  it('separates multiple questions with blank line', () => {
    const out = formatAnswers({ Q1: 'A1', Q2: 'A2' });
    expect(out).toMatch(/Q: Q1\nA: A1\n\nQ: Q2\nA: A2/);
  });

  it('includes preview when annotation present', () => {
    const out = formatAnswers(
      { 'Which layout?': 'Sidebar' },
      { 'Which layout?': { preview: '```\n[ nav | content ]\n```' } },
    );
    expect(out).toContain('selected preview:');
    expect(out).toContain('[ nav | content ]');
  });
});
```

### Step 7.3: 跑测试 + typecheck

- [ ] Run:

```bash
pnpm test && pnpm typecheck
```

Expected: 15 PASS（+3 formatAnswers）；typecheck 无 error。

⚠️ 如果 `tool()` 签名跟我假设的不一样（特别是第 4 个参数 extra 的类型），调整：
- 看 `node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts` 第 5632 行附近的 `function tool<Schema>(_name, _description, _inputSchema, _handler, _extras?)`
- handler 第二个参数实际签名是 `extra: unknown`；从中取 `toolUseId` 是常见 MCP 模式但需要类型 cast

### Step 7.4: Commit

- [ ] Run:

```bash
git add server/src/ask-user-tool.ts server/src/__tests__/ask-user-tool.test.ts
git commit -m "feat(server): AskUserQuestion MCP tool factory + formatAnswers"
```

---

## Task 8: §4 Server — 把 askRegistry 接入 ChatSession + chat-rest

**Files:**
- Modify: `server/src/session-manager.ts`
- Modify: `server/src/chat-rest.ts`（在 §5 SSE 迁移基础上加 AnswerQuestion 路由 + askRegistry per session）

### Step 8.1: ChatSession 注入 askRegistry

- [ ] Modify `server/src/session-manager.ts`：

顶部加 import：
```ts
import { AskUserQuestionRegistry, makeAskUserMcpServer } from './ask-user-tool.js';
```

修改构造器签名：
```ts
constructor(opts: {
  cwd: string;
  permissionMode: PermissionMode;
  resume?: string;
  model?: string;
  askRegistry: AskUserQuestionRegistry;
}) {
  this.cwd = opts.cwd;
  this.permissionMode = opts.permissionMode;
  this.resume = opts.resume;
  this.model = opts.model;
  this.askRegistry = opts.askRegistry;
}
```

并加字段：
```ts
private readonly askRegistry: AskUserQuestionRegistry;
```

修改 `start()` 的 `options` 构造：
```ts
const options: Options = {
  cwd: this.cwd,
  permissionMode: this.permissionMode,
  includePartialMessages: true,
  mcpServers: {
    'ask-user-question': makeAskUserMcpServer(this.askRegistry),
  },
  ...(bypassing ? { allowDangerouslySkipPermissions: true } : {}),
  ...(this.resume ? { resume: this.resume } : {}),
  ...(this.model ? { model: this.model } : {}),
};
```

加新方法（与 `pushUserMessage` 同区域）：
```ts
answerQuestion(
  toolUseId: string,
  answers: Record<string, string>,
  annotations?: Record<string, { preview?: string; notes?: string }>,
): boolean {
  // formatAnswers is imported from ask-user-tool.ts above
  return this.askRegistry.answer(toolUseId, formatAnswers(answers, annotations));
}
```

并在顶部 import 区加：
```ts
import { formatAnswers } from './ask-user-tool.js';
```

### Step 8.2: chat-rest.ts 接入 askRegistry per session + AnswerQuestion 路由

- [ ] Modify `server/src/chat-rest.ts`：

顶部 import 加：
```ts
import { AskUserQuestionRegistry } from './ask-user-tool.js';
import type { AnswerQuestionRequest } from '@cc/shared';
```

修改 `SessionEntry` interface 加字段：
```ts
interface SessionEntry {
  session: ChatSession;
  buffer: EventBuffer;
  askRegistry: AskUserQuestionRegistry;   // 新增
  graceTimer?: NodeJS.Timeout;
  writers: Set<{ write: (s: string) => void; end: () => void }>;
}
```

在 `POST /chat/start` 处理函数里，创建 `askRegistry` 并传给 `ChatSession`：
```ts
const askRegistry = new AskUserQuestionRegistry();
const session = new ChatSession({
  cwd,
  permissionMode,
  resume: body.resume,
  model: body.model,
  askRegistry,   // 新增
});
const entry: SessionEntry = {
  session,
  buffer: new EventBuffer(),
  askRegistry,   // 存在 entry 里以便后续 reject
  writers: new Set(),
};
```

在 `closeSession()` 里清理 askRegistry：
```ts
function closeSession(id: string): void {
  const entry = sessions.get(id);
  if (!entry) return;
  cancelGrace(entry);
  entry.askRegistry.rejectAll('session closed');   // 新增
  entry.session.close();
  for (const w of entry.writers) {
    try { w.end(); } catch { /* */ }
  }
  sessions.delete(id);
}
```

新增 `POST /chat/:id/answer-question` 路由（放在其它路由之间，例如 `set-permission-mode` 之后）：
```ts
app.post<{ Params: { id: string }; Body: AnswerQuestionRequest }>(
  '/chat/:id/answer-question',
  async (req, reply) => {
    const entry = sessions.get(req.params.id);
    if (!entry) { reply.code(404); return { error: 'session not found' }; }
    const ok = entry.session.answerQuestion(
      req.body.tool_use_id,
      req.body.answers,
      req.body.annotations,
    );
    if (!ok) {
      // 答得太晚 / tool_use_id 不存在 —— 不致命，记 log
      app.log.warn({ toolUseId: req.body.tool_use_id }, 'answer_question: no pending tool');
    }
    return { ok };
  },
);
```

### Step 8.3: typecheck + 跑测试

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion/server
pnpm typecheck && pnpm test
```

Expected: 无 error；15 测试仍 PASS。

### Step 8.4: 手动 smoke（curl + SSE）

- [ ] 启 server `pnpm dev`，新 terminal：

```bash
# 起一个会话
START=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"cwd":"<CWD>"}' http://localhost:8787/chat/start)
SID=$(echo $START | jq -r .session_id)

# 后台监听 SSE
curl -s --no-buffer "http://localhost:8787/chat/$SID/events" > /tmp/sse.log &
SSE_PID=$!
sleep 1

# 让 Claude 调 AskUserQuestion
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"请用 AskUserQuestion 工具向我问一个简单的偏好问题，给我 3 个选项"}' \
  "http://localhost:8787/chat/$SID/message"

# 等几秒让 Claude 调用工具
sleep 10
grep "AskUserQuestion" /tmp/sse.log | head -3
# 应该能从 SSE 流里看到 tool_use 块，name 是 mcp__ask-user-question__AskUserQuestion
# 取出其中 tool_use_id、question text、option label

TOOL_ID="<从 SSE 抠出来的 id>"
Q="<input.questions[0].question>"
A="<input.questions[0].options[0].label>"

# 模拟客户端回答
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"tool_use_id\":\"$TOOL_ID\",\"answers\":{\"$Q\":\"$A\"}}" \
  "http://localhost:8787/chat/$SID/answer-question"

# 应该看到 SSE 继续流出 assistant 消息（Claude 收到答案后继续生成）
sleep 15
tail -50 /tmp/sse.log

# 清理
kill $SSE_PID
curl -X DELETE "http://localhost:8787/chat/$SID"
```

### Step 8.5: Commit

- [ ] Run:

```bash
git add server/src/session-manager.ts server/src/chat-rest.ts
git commit -m "feat(server): wire AskUserQuestion into chat-rest + ChatSession"
```

---

## Task 9: §4 Client — AskUserQuestionWidget skeleton + dispatch

**目标**：先把"已答态"和"路由分发"接好，确认整条链路通；live form 留到 Task 10。

**Files:**
- Create: `app/lib/widgets/ask_user_question.dart`
- Modify: `app/lib/widgets/message_view.dart`

### Step 9.1: 写 AskUserQuestionWidget 骨架（仅 answered state）

- [ ] Create `app/lib/widgets/ask_user_question.dart`:

```dart
import 'package:flutter/material.dart';

import '../api/protocol.dart';
import '../theme.dart';

class AskUserQuestionWidget extends StatefulWidget {
  final ToolUseBlock toolUse;
  /// 已配对的 tool_result；非空 = answered 态
  final ToolResultBlock? answeredResult;
  /// 提交回调：把答案 + annotations 通过 ws 发回 server
  final void Function(
    String toolUseId,
    Map<String, String> answers,
    Map<String, Map<String, String>>? annotations,
  ) onSubmit;

  const AskUserQuestionWidget({
    super.key,
    required this.toolUse,
    required this.answeredResult,
    required this.onSubmit,
  });

  @override
  State<AskUserQuestionWidget> createState() => _AskUserQuestionWidgetState();
}

class _AskUserQuestionWidgetState extends State<AskUserQuestionWidget> {
  late final List<_Question> _questions;

  @override
  void initState() {
    super.initState();
    _questions = _parseQuestions(widget.toolUse.input);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final answered = widget.answeredResult != null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Opacity(
        opacity: answered ? 0.75 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final q in _questions) ...[
              _QuestionPanel(question: q, readOnly: answered),
              const SizedBox(height: 24),
            ],
            if (answered)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '（已答）',
                  style: TextStyle(color: t.textDim, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Question {
  final String question;
  final String header;
  final bool multiSelect;
  final List<_Option> options;
  _Question({
    required this.question,
    required this.header,
    required this.multiSelect,
    required this.options,
  });
}

class _Option {
  final String label;
  final String description;
  final String? preview;
  _Option({required this.label, required this.description, this.preview});
}

List<_Question> _parseQuestions(Map<String, dynamic> input) {
  final list = (input['questions'] as List?) ?? [];
  return list.map((q) {
    final m = q as Map<String, dynamic>;
    final opts = (m['options'] as List).map((o) {
      final om = o as Map<String, dynamic>;
      return _Option(
        label: om['label'] as String,
        description: om['description'] as String? ?? '',
        preview: om['preview'] as String?,
      );
    }).toList();
    return _Question(
      question: m['question'] as String,
      header: m['header'] as String,
      multiSelect: (m['multiSelect'] as bool?) ?? false,
      options: opts,
    );
  }).toList();
}

class _QuestionPanel extends StatelessWidget {
  final _Question question;
  final bool readOnly;
  const _QuestionPanel({required this.question, required this.readOnly});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // header chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: t.accentSubt,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                question.header,
                style: TextStyle(
                  fontSize: 10,
                  color: t.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                question.question,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 占位：options 渲染在 Task 10 实现
        for (final o in question.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surfaceHi,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.label, style: TextStyle(fontSize: 14, color: t.text, fontWeight: FontWeight.w500)),
                  if (o.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        o.description,
                        style: TextStyle(fontSize: 12, color: t.textMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
```

### Step 9.2: 在 message_view.dart 增加分发分支

- [ ] Modify `app/lib/widgets/message_view.dart`：

顶部 import 加：
```dart
import 'ask_user_question.dart';
```

`MessageView` 类需要接受一个回调来发回答案。改它的构造：
```dart
class MessageView extends StatelessWidget {
  final IncomingMessage message;
  final Map<String, ToolResultBlock>? toolResults;
  final void Function(
    String toolUseId,
    Map<String, String> answers,
    Map<String, Map<String, String>>? annotations,
  )? onAnswerQuestion;

  const MessageView({
    super.key,
    required this.message,
    this.toolResults,
    this.onAnswerQuestion,
  });
  // ...
}
```

在 `_renderBlock(context, b)` 内（用 grep 找到 `_renderBlock` 方法），最前面的 `if (b is ToolUseBlock)` 分支改为：

```dart
if (b is ToolUseBlock) {
  if (b.name.endsWith('AskUserQuestion') && onAnswerQuestion != null) {
    final answered = toolResults?[b.id];
    return AskUserQuestionWidget(
      toolUse: b,
      answeredResult: answered,
      onSubmit: onAnswerQuestion!,
    );
  }
  return ToolCallCard(toolUse: b, result: toolResults?[b.id]);
}
```

⚠️ 若现有代码没有这种结构，搜 `ToolCallCard(` 的调用点替换即可。

### Step 9.3: 在 chat_tab.dart 把回调挂上去

- [ ] 找到 `MessageView(...)` 的调用点（grep `MessageView(`），加 `onAnswerQuestion` 参数：

```dart
MessageView(
  message: msg,
  toolResults: toolResults,
  onAnswerQuestion: _sendAnswerQuestion,
)
```

在 `_ChatTabState` 加方法：

```dart
void _sendAnswerQuestion(
  String toolUseId,
  Map<String, String> answers,
  Map<String, Map<String, String>>? annotations,
) {
  if (_sessionId == null || _chatApi == null) return;
  unawaited(_chatApi!.answerQuestion(_sessionId!, toolUseId, answers, annotations));
}
```

⚠️ 这里调用的是 Task 2c.2 创建的 `_chatApi.answerQuestion(...)` 方法 —— REST `POST /chat/<id>/answer-question`，不再走 WS。

### Step 9.4: flutter analyze

- [ ] Run:

```bash
flutter analyze lib/widgets/ask_user_question.dart lib/widgets/message_view.dart lib/screens/tabs/chat_tab.dart
```

Expected: 无 error。

### Step 9.5: 手动 smoke

- [ ] 启 server + app
- [ ] 让 Claude 调 AskUserQuestion
- [ ] 看到一张卡片，question + header chip + options 都渲染了；点 option 暂时无反应（live form 留到下个 task）
- [ ] 等 30 min 超时后看到 Claude 继续生成 + cardanswered

### Step 9.6: Commit

- [ ] Run:

```bash
git add app/lib/widgets/ask_user_question.dart app/lib/widgets/message_view.dart app/lib/screens/tabs/chat_tab.dart
git commit -m "feat(chat): AskUserQuestion widget skeleton + dispatch"
```

---

## Task 10: §4 Client — Live form（单 Q 单选立即提交 + multi-select / 多 Q 提交按钮模式）

**目标**：让卡片可交互。

**Files:**
- Modify: `app/lib/widgets/ask_user_question.dart`

### Step 10.1: 改写 _AskUserQuestionWidgetState 加交互状态

- [ ] 在 `_AskUserQuestionWidgetState` 内添加：

```dart
/// 用户当前选择：questionIdx → 选中的 option label 集合
/// 单选时集合 size ≤ 1；多选时可多。
final List<Set<String>> _selections = [];
/// 自定义文本（"Other" 输入），questionIdx → 文本（与 _selections 互斥：选择 'Other' 后写入）
final Map<int, String> _customTexts = {};
bool _submitted = false;
```

`initState()` 末尾加：
```dart
for (int i = 0; i < _questions.length; i++) {
  _selections.add(<String>{});
}
```

### Step 10.2: 决定模式（即时 vs form）

- [ ] 加 getter：

```dart
bool get _isFormMode {
  if (_questions.length > 1) return true;
  return _questions.any((q) => q.multiSelect);
}
```

### Step 10.3: 改 build() 处理 live 态

- [ ] 把 `build()` 中 `Opacity` 包裹的 children 调整：

```dart
child: Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (int i = 0; i < _questions.length; i++) ...[
      _QuestionInteractivePanel(
        index: i,
        question: _questions[i],
        readOnly: answered || _submitted,
        selected: _selections[i],
        customText: _customTexts[i],
        onTapOption: (label) => _onTapOption(i, label),
        onCustomTextSubmitted: (text) => _onCustomText(i, text),
      ),
      if (i < _questions.length - 1) const SizedBox(height: 24),
    ],
    if (!answered && _isFormMode && !_submitted) ...[
      const SizedBox(height: 16),
      _SubmitButton(
        enabled: _canSubmit(),
        onTap: _submit,
      ),
    ],
    if (answered)
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '（已答）',
          style: TextStyle(color: t.textDim, fontSize: 12),
        ),
      ),
  ],
),
```

### Step 10.4: 加交互方法

- [ ] 在 `_AskUserQuestionWidgetState` 加：

```dart
void _onTapOption(int qIdx, String label) {
  final q = _questions[qIdx];
  setState(() {
    if (q.multiSelect) {
      if (_selections[qIdx].contains(label)) {
        _selections[qIdx].remove(label);
      } else {
        _selections[qIdx].add(label);
      }
      // 取消自定义文本（如果之前选过）
      _customTexts.remove(qIdx);
    } else {
      _selections[qIdx]
        ..clear()
        ..add(label);
      _customTexts.remove(qIdx);
    }
  });
  // 单 Q 单选 + 非 form 模式：立即提交
  if (!_isFormMode && !q.multiSelect) {
    _submit();
  }
}

void _onCustomText(int qIdx, String text) {
  if (text.isEmpty) return;
  setState(() {
    _customTexts[qIdx] = text;
    _selections[qIdx]
      ..clear()
      ..add('__OTHER__');
  });
  if (!_isFormMode) {
    _submit();
  }
}

bool _canSubmit() {
  for (int i = 0; i < _questions.length; i++) {
    if (_selections[i].isEmpty && _customTexts[i] == null) return false;
  }
  return true;
}

void _submit() {
  if (_submitted || widget.answeredResult != null) return;
  if (!_canSubmit()) return;

  final answers = <String, String>{};
  final annotations = <String, Map<String, String>>{};
  for (int i = 0; i < _questions.length; i++) {
    final q = _questions[i];
    final selected = _selections[i];
    final custom = _customTexts[i];
    String answer;
    if (custom != null && selected.contains('__OTHER__')) {
      answer = custom;
    } else if (q.multiSelect) {
      answer = selected.join(', ');
    } else {
      answer = selected.first;
    }
    answers[q.question] = answer;
    // 把所选 option 的 preview 一并回传（仅单选有 preview）
    if (!q.multiSelect && !selected.contains('__OTHER__')) {
      final picked = q.options.firstWhere(
        (o) => o.label == selected.first,
        orElse: () => _Option(label: '', description: ''),
      );
      if (picked.preview != null) {
        annotations[q.question] = {'preview': picked.preview!};
      }
    }
  }
  setState(() => _submitted = true);
  widget.onSubmit(
    widget.toolUse.id,
    answers,
    annotations.isEmpty ? null : annotations,
  );
}
```

### Step 10.5: 实现 _QuestionInteractivePanel

- [ ] 在文件末尾追加（替换前一版的占位 `_QuestionPanel`，可以删掉）：

```dart
class _QuestionInteractivePanel extends StatelessWidget {
  final int index;
  final _Question question;
  final bool readOnly;
  final Set<String> selected;
  final String? customText;
  final void Function(String label) onTapOption;
  final void Function(String text) onCustomTextSubmitted;

  const _QuestionInteractivePanel({
    required this.index,
    required this.question,
    required this.readOnly,
    required this.selected,
    required this.customText,
    required this.onTapOption,
    required this.onCustomTextSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // header + question
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: t.accentSubt,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                question.header,
                style: TextStyle(
                  fontSize: 10,
                  color: t.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                question.question,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // options
        for (final o in question.options)
          _OptionTile(
            option: o,
            selected: selected.contains(o.label),
            multiSelect: question.multiSelect,
            disabled: readOnly,
            onTap: () {
              if (readOnly) return;
              onTapOption(o.label);
            },
          ),
        // "Other" 一行
        _OtherTile(
          selected: selected.contains('__OTHER__'),
          customText: customText,
          disabled: readOnly,
          onTap: () async {
            if (readOnly) return;
            final result = await showDialog<String>(
              context: context,
              builder: (ctx) => _CustomInputDialog(initial: customText ?? ''),
            );
            if (result != null && result.isNotEmpty) {
              onCustomTextSubmitted(result);
            }
          },
        ),
        // readOnly 时展示用户当时选了什么
        if (readOnly && selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              selected.contains('__OTHER__')
                  ? '→ 你输入了：${customText ?? ''}'
                  : '→ 你选了：${selected.join(', ')}',
              style: TextStyle(fontSize: 12, color: t.textMuted),
            ),
          ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final _Option option;
  final bool selected;
  final bool multiSelect;
  final bool disabled;
  final VoidCallback onTap;
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.multiSelect,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? t.accentSubt : t.surfaceHi,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? t.accent.withValues(alpha: 0.5) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (multiSelect)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: Icon(
                    selected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 18,
                    color: selected ? t.accent : t.textMuted,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(fontSize: 14, color: t.text, fontWeight: FontWeight.w500),
                    ),
                    if (option.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          option.description,
                          style: TextStyle(fontSize: 12, color: t.textMuted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              // Preview 触发图标（Task 11 接 bottom sheet）
              if (option.preview != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.visibility_outlined, size: 18, color: t.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtherTile extends StatelessWidget {
  final bool selected;
  final String? customText;
  final bool disabled;
  final VoidCallback onTap;
  const _OtherTile({
    required this.selected,
    required this.customText,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? t.accentSubt : t.surfaceHi,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? t.accent.withValues(alpha: 0.5) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16, color: t.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selected && customText != null && customText!.isNotEmpty
                      ? customText!
                      : '自定义…',
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: selected ? t.text : t.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomInputDialog extends StatefulWidget {
  final String initial;
  const _CustomInputDialog({required this.initial});

  @override
  State<_CustomInputDialog> createState() => _CustomInputDialogState();
}

class _CustomInputDialogState extends State<_CustomInputDialog> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return AlertDialog(
      backgroundColor: t.surface,
      title: Text('自定义输入', style: TextStyle(color: t.text, fontSize: 16)),
      content: TextField(
        controller: _c,
        autofocus: true,
        cursorColor: t.accent,
        style: TextStyle(color: t.text, fontSize: 14),
        decoration: InputDecoration(
          hintText: '输入你的回答…',
          hintStyle: TextStyle(color: t.textDim),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: t.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_c.text.trim()),
          child: Text('确定', style: TextStyle(color: t.accent)),
        ),
      ],
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _SubmitButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = enabled
        ? (dark ? t.text : const Color(0xFF101828))
        : (dark ? t.borderSubt : const Color(0xFFD0D5DD));
    final fg = enabled
        ? (dark ? const Color(0xFF0B1210) : Colors.white)
        : (dark ? t.textDim : Colors.white);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          '提交',
          style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
```

记得删除上一版的占位 `_QuestionPanel` 类（被 `_QuestionInteractivePanel` 替代）。

### Step 10.6: flutter analyze

- [ ] Run:

```bash
flutter analyze lib/widgets/ask_user_question.dart
```

Expected: 无 error。如果 `dark` 变量在 `_QuestionInteractivePanel.build` 被声明但未用，删掉。

### Step 10.7: 手动 smoke

- [ ] 让 Claude 调 AskUserQuestion (单 Q 单选)，tap option → 立即提交、卡片冻结、Claude 继续
- [ ] 让 Claude 调 multiSelect 版本 → option 出现 checkbox，必须按"提交"才发
- [ ] 让 Claude 一次问 2 个 question → form 模式
- [ ] 选 "自定义…" → 弹 dialog 输入 → 提交后回传成自定义文本

### Step 10.8: Commit

- [ ] Run:

```bash
git add app/lib/widgets/ask_user_question.dart
git commit -m "feat(chat): AskUserQuestion interactive form (single/multi/Other)"
```

---

## Task 11: §4 Client — Preview bottom sheet

**Files:**
- Modify: `app/lib/widgets/ask_user_question.dart::_OptionTile`

### Step 11.1: 给 _OptionTile preview 图标加 onTap

- [ ] 把 `_OptionTile` 改为 `StatefulWidget` 或直接外层包 `GestureDetector` —— 但 preview 图标在右侧需要独立 hitTest。最稳妥：把它包成独立可点的 button：

修改 `_OptionTile` 的 preview 部分：

```dart
// 替换：
if (option.preview != null)
  Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Icon(Icons.visibility_outlined, size: 18, color: t.textMuted),
  ),

// 改为：
if (option.preview != null)
  GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => _showPreview(context, option.label, option.preview!),
    child: Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Icon(Icons.visibility_outlined, size: 18, color: t.textMuted),
    ),
  ),
```

在 `_OptionTile` 类内 / 或顶级函数：

```dart
void _showPreview(BuildContext context, String optionLabel, String preview) {
  final t = AppTokens.of(context);
  // HTML 检测：粗暴判断 < + > 配对模式
  final looksHtml = RegExp(r'<\s*\w+[^>]*>').hasMatch(preview);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx2, scroll) {
          return Container(
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          optionLabel,
                          style: TextStyle(color: t.text, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: t.textMuted),
                        onPressed: () => Navigator.of(ctx2).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(color: t.borderSubt, height: 1, thickness: 0.5),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: looksHtml
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: t.warning.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: t.warning.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  'Preview 是 HTML，暂不支持富文本渲染，显示原文：',
                                  style: TextStyle(fontSize: 11, color: t.warning),
                                ),
                              ),
                              SelectableText(
                                preview,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: t.textMuted,
                                ),
                              ),
                            ],
                          )
                        : MarkdownBody(
                            data: preview,
                            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(ctx2)),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
```

顶部 imports 加（若未有）：
```dart
import 'package:flutter_markdown/flutter_markdown.dart';
```

### Step 11.2: flutter analyze

- [ ] Run:

```bash
flutter analyze lib/widgets/ask_user_question.dart
```

Expected: 无 error。

### Step 11.3: 手动 smoke

- [ ] 让 Claude 用 AskUserQuestion 给 option 加 markdown preview（在 prompt 里要求："给每个选项加一段 markdown 代码块作为 preview"）
- [ ] tap 选项右侧 👁 图标 → 弹底部 sheet，markdown 渲染正常
- [ ] 下拉关闭 / tap × 关闭

### Step 11.4: Commit

- [ ] Run:

```bash
git add app/lib/widgets/ask_user_question.dart
git commit -m "feat(chat): AskUserQuestion preview bottom sheet (markdown + HTML fallback)"
```

---

## Task 12: 端到端验收 + 收尾

### Step 12.1: 全量分析

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion
pnpm -r typecheck
cd app && flutter analyze
```

Expected: 全部无 error。

### Step 12.2: 全量测试

- [ ] Run:

```bash
cd /Users/airoucat/workspace/shulex/claude-companion/server
pnpm test
```

Expected: 15 PASS。

### Step 12.3: 端到端 smoke

依次跑完整流程：

- [ ] 启 server 和 app
- [ ] 亮 / 暗模式分别打开
- [ ] 按钮：观察发送 / 停止按钮的黑白主题渲染
- [ ] 附件：选 1 图 + 1 PDF + 1 文本，看 chip 上传过程，发送，让 Claude `Read` 图和 PDF
- [ ] 对象 tool 输出：让 Claude 跑一个返回 JSON 的 MCP 工具或 `WebSearch`，观察输出是美化 JSON 而不是 `[object Object]`
- [ ] AskUserQuestion 完整流程：
  - 单 Q 单选 instant submit
  - 单 Q 多选 + 提交
  - 多 Q form
  - 自定义输入
  - preview bottom sheet（让 Claude 给某个 option 带 markdown preview）
- [ ] 验证所有 commit log：

```bash
git log --oneline | head -20
```

Expected: 看到 12 个本 plan 的 commit + Pre-flight 的 1 个清理 commit + Spec commit。

### Step 12.4: 最后清理 commit（如果有）

如果实施过程中产生了零散修复（typo / lint），最后归一个 commit：

- [ ] Run:

```bash
git add -A
git status --short  # 确认范围
git commit -m "chore: misc polish from Spec A implementation"
```

---

## Self-Review

**Spec coverage check**：

| Spec section | 对应 Task |
|---|---|
| §1 按钮 | Task 2 |
| §2 附件 | Task 3 (server) + Task 4 (client) |
| §3a tool_result JSON | Task 1 |
| §3b tool_use input JSON | Task 1b |
| §4.1-4.2 架构 + Server | Task 6 + 7 + 8 |
| §4.3 协议（REST 类型） | Task 5 |
| §4.3-4.4 Client 渲染 | Task 9 (skeleton) + 10 (form) + 11 (preview) |
| §4.6 妥协 | 已记入 |
| §5 SSE Server | Task 2b |
| §5 SSE Client + WS 删除 | Task 2c |

**Placeholder scan**：plan 内无 TBD / TODO / "fill in"。每个 code step 都有完整代码。每个测试 step 都有 expected output。

**Type consistency**：
- `_AttachmentState` / `_AttachmentStatus` 在 Task 4 定义后在 Task 4.7、4.8 一致使用
- `AskUserQuestionRegistry` 的 `register / answer / rejectAll` 签名在 Task 6 定义后 Task 8 一致使用
- `_Question / _Option` 内部模型在 Task 9 定义后 Task 10 沿用
- `MessageView.onAnswerQuestion` 签名 Task 9 定义后 chat_tab 在 Step 9.3 一致传入
