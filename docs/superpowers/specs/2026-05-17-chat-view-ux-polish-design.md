# Chat 视图 UX 完善（Spec A）

**日期**：2026-05-17
**作者**：huwei@mkt.voc.ai
**状态**：草案，待 review

## 背景与目标

Claude Companion 的聊天主视图（`ChatTab`）当前可用但有若干长期累积的小痛点。本 spec 把四项独立但主题相关的改进打包成一次提交：

1. 发送 / 停止按钮换成黑白风（参考 `shulex-smart-service/src/pages/cxClaw`）
2. 输入框支持附件上传（图片 / PDF / 任意文件）
3. tool_result 返回的结构化对象当前被渲染成字面量 `[object Object]`，需修复
4. 支持 cc 同款 `AskUserQuestion` 多选/单选交互渲染

主题统一为"Chat 视图体验完善"，每一项都能独立验收；放在同一份 spec 里是因为代码改动有局部交叉（输入框、协议、tool 渲染），合并一次实现+审查比拆四次更经济。

**非目标**（明确排除）：

- 多会话同时跑 + 后台运行 → 留给独立 Spec B
- 端到端历史会话搜索 / 全文检索
- 输入框语音输入
- AskUserQuestion 的 HTML preview（仅支持 markdown preview）
- 附件目录的自动清理

## 现状速览

**APP（Flutter）**

- `screens/tabs/chat_tab.dart::_Composer`：单行输入 + 44×44 圆角方块发送按钮（`accent` 绿底，busy 时 `error` 红底）
- `widgets/message_view.dart`：assistant / user / tool 消息分发器
- `widgets/tool_call_card.dart`：tool_use + tool_result 配对渲染，`_extractText` 拼装 result 内容；底色 `t.bg`、monospace 字体
- 主题 token：`theme.dart::AppTokens`（light + dark 双套）

**Server（Node + Fastify）**

- `ws-chat.ts`：单 socket 单 session；客户端协议 `init / user_message / set_model / set_permission_mode / interrupt / ping`
- `session-manager.ts::ChatSession`：包装 SDK `query()`，输入 async iterator，`pushUserMessage(text: string)` 只接受字符串
- `serialize.ts::normalizeToolResultContent`：把 SDK tool_result.content 转 wire 格式，**对 object 使用 `String(obj)` 得到 `"[object Object]"`** —— 即 bug 根源

**参考标的**：`shulex-smart-service/src/pages/cxClaw/Chat/index.module.less`
- `.sendBtn`：40×40 圆形、`#101828` 黑底 + 白图标、`box-shadow: 0 2px 6px rgba(16,24,40,.15)`、hover translateY(-1px)
- `.stopSquare`：同按钮中央 10×10 白方块
- `.attachmentChip`：浅灰 chip、文件名 + spinner / `×` 移除
- `.plusBtn`：左侧 32×32 透明按钮，hover 浅灰

## 设计

### 1. 发送 / 停止按钮（黑白风）

**改动位置**：`app/lib/screens/tabs/chat_tab.dart::_SendOrStopButton`

**视觉规格**：

| 模式 | 状态 | 背景色 | 图标 / 方块色 |
|---|---|---|---|
| 亮 | 可发送 | `#101828` | 白 |
| 亮 | busy（显示停止） | `#101828` | 白色 10×10 方块（自绘） |
| 亮 | 不可发 | `#D0D5DD` | 白 |
| 暗 | 可发送 | `t.text` = `#E6E6E6` | 黑 = `#0B1210` |
| 暗 | busy（显示停止） | `t.text` | 黑色 10×10 方块 |
| 暗 | 不可发 | `t.borderSubt` | `t.textDim` |

- 尺寸：40×40，`borderRadius: 9999`（圆形）
- 阴影：`BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: Offset(0, 2))`
- 发送图标：`Icons.arrow_upward_rounded` size 18
- 停止图标：自绘 `Container` 10×10，圆角 2，色 = 文字色
- 点击反馈：用 `GestureDetector` + `AnimatedScale(0.96 on tapDown, 1.0 on tapUp)`，0.1s curve

**移除**：原来 busy 态使用 `t.error` 红底的逻辑。停止按钮和发送按钮颜色一致，仅图标区别。

### 2. 附件上传

#### 用户流程

```
用户 tap [+] 按钮
  → 调起系统 file picker（多选 ≤ 10）
  → 立即开始上传到 server（用户能继续输入文本）
  → composer 上方出现 chip 行，每个 chip 显示 spinner
  → 上传成功 → spinner 替换为 × 关闭按钮
  → 上传失败 → chip 变红边 + ! 图标，tap 重试
  → 任一 chip 仍在上传 → 发送按钮禁用（不可发送）
  → 全部上传完 → 发送按钮可点 → 用户按发送
  → composer 文本拼接为：
       <用户输入文本>
       \n\n附件：\n`/abs/path/1`\n`/abs/path/2`
  → 走现有 user_message 协议
```

#### Server 端改动

**新建 `server/src/upload.ts`**：

```ts
// POST /upload?cwd=<urlencoded>
// multipart/form-data, field name = "file"
// 单文件 ≤ 25MB，校验 isPathAllowed(cwd)
// 落盘到 <cwd>/.claude/attachments/<YYYYMMDD-HHmmss-mmm>-<sanitized-name>
// 返回 { path: string, size: number }
```

- 注册到 `server/src/index.ts` 的 Fastify 实例
- 使用 `@fastify/multipart` 处理 multipart
- 文件名 sanitize：剥离路径分隔符，保留 ASCII 字母数字 + `.-_`，其余替换为 `_`
- 失败返回 4xx + JSON `{ error: string }`
- 目录不存在则递归创建

**不做**：自动清理、缩略图生成、HEIC 转 JPG（HEIC 原样落盘；Claude `Read` 能处理）

#### Client 端改动

**`pubspec.yaml`** 新增：`file_picker: ^8.x`

**`app/lib/api/upload_api.dart`**（新文件）：
- `UploadApi(httpBase).upload(File, cwd) → Future<UploadedFile>`
- `UploadedFile { String path; int size; }`

**`app/lib/screens/tabs/chat_tab.dart::_Composer`**：

布局重构（在文本框上方加附件行，工具栏左侧加 `+`）：

```
┌─────────────────────────────────┐
│ [attachmentChip] [chip] [chip]  │  ← 仅当 attachments 非空时显示
│                                 │
│ Ask Claude…                     │  ← TextField
│                                 │
│ [+] [permMode] [model]   [发送]  │  ← 工具栏，[+] 在左
└─────────────────────────────────┘
```

新增状态：
- `List<_AttachmentState> _attachments` （状态：uploading / ready / failed）
- `bool get _canSend => connected && !busy && _attachments.every((a) => a.state == ready)`

**`_AttachmentChip` 新组件**：
- 高度 28、`t.surfaceHi` 底、`t.border` 0.5px、圆角 8、padding 4 left 8 right
- 左侧 file-icon（按 MIME 简单 4 分类：`image/*` 图片图标、`application/pdf` PDF 图标、`text/*` 代码图标、其它通用文件图标）
- 中间 filename：`maxLines: 1`、`overflow: ellipsis`、maxWidth 200
- 右侧：上传中 → `CcSpinner(size: 12)`；ready → tap `Icons.close_rounded` 12px 移除；failed → `Icons.error_outline` 14px 红色 + tap 重试

**`+` 按钮**：
- 在工具栏左侧（`_PermissionModePicker` 之前）
- 32×32 圆形、透明底、`Icons.add_rounded` 20px、色 `t.textMuted`
- tap → `FilePicker.platform.pickFiles(allowMultiple: true)` → 每个文件起 `Future.microtask(() => _uploadOne(file))`

**发送时**的文本拼装（伪代码）：
```dart
final text = _textController.text.trim();
final attachLines = _attachments
    .where((a) => a.state == ready)
    .map((a) => '`${a.path}`')
    .join('\n');
final payload = attachLines.isEmpty
    ? text
    : '$text\n\n附件：\n$attachLines';
// 之后照原路径发 user_message
```

发送完成后清空 `_attachments`。

### 3. tool 输出 / 输入对象渲染修复

**3a. tool_result 输出**（server 侧）— 改动位置：`server/src/serialize.ts::normalizeToolResultContent`

**3b. tool_use 输入**（client 侧）— 改动位置：`app/lib/widgets/tool_call_card.dart::_KeyValueList` + default 分支

**Client 侧问题**：自定义 MCP 工具（如 `mcp__ask-user-question__AskUserQuestion`）的 input 含嵌套 Map/List 时，现有 `_KeyValueList` 用 `.toString()` 渲染，得到 `key: {a: 1, b: 2}` 这种 Dart Map 内联字面量，深层嵌套时不可读。

**修复**：在 `_renderBody` 的 `default` 分支，检测 input 是否含 `Map` / `List` 值；
- 有 → 渲染为 pretty JSON 代码块（monospace + 黑底，跟 tool_result 输出同款）
- 无 → 维持现有 `_KeyValueList` 内联键值

Read / Edit / Bash / Grep / Glob / TodoWrite 等已有专门 renderer 不变。

**3a 修复**：

```ts
function normalizeToolResultContent(content: unknown): any {
  if (content == null) return null;
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content.map((item: any) => {
      if (item && typeof item === 'object' && 'text' in item) {
        const t = item.text;
        const text = typeof t === 'string' ? t : JSON.stringify(t, null, 2);
        return { type: 'text', text };
      }
      if (item && typeof item === 'object' && item.type === 'image') {
        return item; // 保留 image 块（如果将来 vision 走原生）
      }
      return { type: 'text', text: JSON.stringify(item, null, 2) };
    });
  }
  if (typeof content === 'object') {
    return JSON.stringify(content, null, 2);
  }
  return String(content);
}
```

**Client 侧（3a）**：无改动。`tool_call_card.dart::_outputBody` 已经是 monospace + 黑底渲染，pretty JSON 直接好看。

**3b 修复**（client 侧 tool_use input）：

在 `_renderBody` default 分支：

```dart
default:
  final hasNested = input.values.any((v) => v is Map || v is List);
  return hasNested
      ? _JsonBlock(value: input)
      : _KeyValueList(map: input);
```

新增 `_JsonBlock`：

```dart
class _JsonBlock extends StatelessWidget {
  final Object? value;
  const _JsonBlock({required this.value});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    const enc = JsonEncoder.withIndent('  ');
    final text = enc.convert(value);
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
        style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: t.textMuted, height: 1.5),
      ),
    );
  }
}
```

顶部加 `import 'dart:convert';`。

**验证**：测试样本 — 调一个返回 JSON 对象的 MCP 工具，或者用 `Bash` 跑 `echo '{"a":1,"b":[2,3]}'` 然后让 Claude 解释（解释步骤里可能产生包含 JSON 结构的内部 tool_result）。修改前显示 `[object Object]`，修改后显示美化 JSON。

### 4. AskUserQuestion 交互渲染

#### 4.1 架构总流程

```
Claude assistant ──→ SDK 调用 AskUserQuestion 自定义 tool
                       │
                       ▼
                  [server] tool handler 注册 (toolUseId → resolver) 到
                           pendingQuestions Map，返回挂起的 Promise
                       │
                       ▼  tool_use 块经正常 streaming 路径流到客户端
                  [client] message_view 检测 name === 'AskUserQuestion'
                           → 渲染 AskUserQuestionWidget（live 态）
                       │
                       ▼  用户填表 → 提交
                  [client] WS 发送 { type: 'answer_question', tool_use_id, answers }
                       │
                       ▼
                  [server] WS handler → 找到 resolver → 格式化 answer string
                           → resolver(callToolResult) → Promise 兑现
                       │
                       ▼
                  SDK 把 tool_result 写回会话 → Claude 继续生成
```

#### 4.2 Server 改动

**新建 `server/src/ask-user-tool.ts`**：

```ts
import { createSdkMcpServer, tool } from '@anthropic-ai/claude-agent-sdk';
import { z } from 'zod';

type Resolver = (result: CallToolResult) => void;
type Rejecter = (err: Error) => void;

export class AskUserQuestionRegistry {
  private pending = new Map<string, { resolve: Resolver; reject: Rejecter }>();

  register(toolUseId: string): Promise<CallToolResult> {
    return new Promise((resolve, reject) => {
      this.pending.set(toolUseId, { resolve, reject });
      setTimeout(() => {
        if (this.pending.has(toolUseId)) {
          this.pending.delete(toolUseId);
          reject(new Error('User did not answer within 30 minutes'));
        }
      }, 30 * 60 * 1000);
    });
  }

  answer(toolUseId: string, formatted: string): boolean {
    const entry = this.pending.get(toolUseId);
    if (!entry) return false;
    this.pending.delete(toolUseId);
    entry.resolve({ content: [{ type: 'text', text: formatted }] });
    return true;
  }

  rejectAll(reason: string): void {
    for (const { reject } of this.pending.values()) {
      reject(new Error(reason));
    }
    this.pending.clear();
  }
}

export function makeAskUserMcpServer(registry: AskUserQuestionRegistry) {
  return createSdkMcpServer({
    name: 'ask-user-question',
    tools: [
      tool(
        'AskUserQuestion',
        ASK_USER_QUESTION_DESCRIPTION,
        zQuestionsSchema,
        async (input, { toolUseId }) => registry.register(toolUseId)
      ),
    ],
  });
}
```

- Zod schema `zQuestionsSchema` 完整复刻 cc `prompt.ts` 中的 `inputSchema`：`questions: Array<{ question, header, options: Array<{ label, description, preview? }>, multiSelect? }>`，含 `min(1).max(4)` / `min(2).max(4)` 约束
- 工具描述照搬 cc 的 `ASK_USER_QUESTION_TOOL_PROMPT`，**但移除"Plan mode note"那一段**（cc 那段引用 `EXIT_PLAN_MODE_TOOL_NAME`，claude-companion 不暴露该工具，照搬会让 Claude 误调）
- SDK MCP server 通常会把 tool 名前缀化成 `mcp__<server-name>__<tool-name>` 形式（这里就是 `mcp__ask-user-question__AskUserQuestion`）；客户端 / 序列化层做检测时**用后缀匹配**：`name.endsWith('AskUserQuestion')`，避免硬编码完整 prefix 在 SDK 改版时 break

**修改 `session-manager.ts`**：

- `ChatSession` 构造时收 `askRegistry: AskUserQuestionRegistry`（每条 socket 一个）
- `start()` 时把 `makeAskUserMcpServer(askRegistry)` 加入 `Options.mcpServers`
- 新增 `answerQuestion(toolUseId: string, answers: Record<string,string>, annotations?: Record<string, { preview?: string; notes?: string }>): boolean`：
  - 把每个 question 的 answer 拼成多行 string（复刻 cc `AskUserQuestionTool.tsx` line 226-241），每问一段：
    ```
    Q: <question text>
    A: <answer label or custom text>
    [selected preview:
    <preview content>]    ← 仅当 annotations[question].preview 存在时
    [notes:
    <notes>]              ← 仅当 annotations[question].notes 存在时
    ```
  - 多个 question 之间用空行分隔
  - 最终格式：`User has answered your questions:\n\n<拼装的多段>\n\nYou can now continue with the user's answers in mind.`
  - 调 `askRegistry.answer(toolUseId, formatted)`，返回是否成功

**修改 `ws-chat.ts`**：

- 每 socket 创建一个 `AskUserQuestionRegistry` 实例并传入 `ChatSession`
- 新增 case `'answer_question'`：调 `session.answerQuestion(...)`，不报错也不阻塞 busy
- `socket.on('close')` / `on('error')` 时调 `registry.rejectAll('socket closed')`

#### 4.3 Client 渲染分发

**修改 `app/lib/widgets/message_view.dart`**：

`AssistantMsg` 渲染 content blocks 时，对 `ToolUseBlock` 增加分支：

```dart
Widget _renderBlock(BuildContext context, ContentBlock b) {
  if (b is ToolUseBlock) {
    if (b.name.endsWith('AskUserQuestion')) {   // 后缀匹配，兼容 SDK MCP 前缀
      final answered = toolResults?[b.id];
      return AskUserQuestionWidget(
        toolUse: b,
        answeredResult: answered,
      );
    }
    return ToolCallCard(toolUse: b, result: toolResults?[b.id]);
  }
  // ... 现有分支
}
```

`AskUserQuestionWidget`（新建 `widgets/ask_user_question.dart`）：
- 解析 `b.input` 为 `List<_Question>`（与 cc schema 对齐）
- 若 `answeredResult != null` → 渲染只读"已答"卡片
- 否则 → 渲染交互表单

#### 4.4 交互表单 UI 规格

**整体卡片**：
- 圆角 14、`t.surface` 底、`t.border` 0.5px、padding 16
- 顶部 row：`headerChip`（accent 浅底圆角胶囊 4 left 6 right 高 20）+ question text（fontSize 15 w600）
- 多 question 时垂直堆叠，section 间距 24

**单 question + 单 select + 无 preview（最常见 ~80% 场景）**：
- option 列表，每项 48 高、`t.surfaceHi` 底、圆角 10、padding 12
- 主行：label（fontSize 14 w500）
- 副行：description（fontSize 12 textMuted），最多 2 行省略
- **tap option 即立即提交** → 选中行高亮 0.2s 反馈 → 发送 `answer_question` → 卡片冻结成 answered 态

**多 select**：
- option 行末尾改成 `Checkbox`（24×24，accent 色）
- 卡片底部增加 "提交" 全宽按钮（黑白主题、40 高、圆角 10）
- disabled 直到至少选 1 个

**多 question（一个 tool_use 内 2-4 个 question）**：
- 每个 question 独立 panel + section 标题
- 强制进入 form 模式（统一底部 "提交" 按钮），无论单/多 select
- "提交" 按钮在最末

**"Other"（自定义输入）**：
- 显式渲染：每个 question 选项列表末尾固定加一行 "💬 自定义…"（icon `Icons.edit_outlined`）
- tap → `showDialog`：标题 = question 缩略 + "自定义输入"、`TextField` autofocus、按钮"取消 / 确定"
- 确定后：在 form 状态里把该 question 的 answer 标记为该自定义文本
- 单 question 单 select 模式下，输入完确定 = 立即提交

**Preview 支持**：
- 当 option.preview 存在时，option 行右侧出现 `Icons.visibility_outlined` 18px 灰色图标按钮
- tap → `showModalBottomSheet`，高度 90%、`DraggableScrollableSheet` 可下拉关闭
- 内容用 `MarkdownBody` 渲染（已有 `flutter_markdown` 依赖）
- 若 server 发来的 preview 是 HTML（有 `<html>/<body>/<div>` 等标签且 markdown 解析空），fallback 成"原文 + 顶部提示『preview 暂不支持富文本，显示原文』"

**已答状态**：
- 整张卡片 `Opacity(0.75)`
- 每个 question 行下方紧跟 `→ 你选了：<label>`（或 `→ 你输入了：<custom text>`）
- 所有交互元素禁用（不显示 spinner、checkbox 锁死）

#### 4.5 协议扩展

`packages/shared/src/protocol.ts`：

```ts
// client → server: 新增
type ClientAnswerQuestionMessage = {
  type: 'answer_question';
  tool_use_id: string;
  answers: Record<string, string>;   // questionText → option label 或自定义文本
  annotations?: Record<string, { preview?: string; notes?: string }>;
};

// ChatClientMessage 加入这一支
type ChatClientMessage = ... | ClientAnswerQuestionMessage;
```

**Client 何时填 `annotations`**：

- 用户选了一个**有 preview 的 option** → client 把该 option.preview 的原文塞进
  `annotations[questionText] = { preview: <option.preview 原文> }`
  这样 Claude 知道用户当时看到的是什么内容，避免它复述时偏离用户视野
- `notes` 字段 Spec A 阶段不使用，保留协议字段为未来"用户可以加备注"扩展
- 没有 preview 的选项 / 自定义输入：不需要塞 `annotations`，省传输

**Server → Client**：无新增。`tool_use` / `tool_result` 走现有 assistant / user 消息流路径。

#### 4.6 已知妥协 / YAGNI

- HTML preview 不渲染（仅 markdown）
- 30 分钟超时后会话继续，tool_result 会带 is_error。Claude 自适应处理。
- 用户切后台不暂停超时（实现成本）。已记入"将来再说"。
- 撤回上一答：不支持。一答即终态。
- 用户提交后即冻结，即便 server 因网络问题没收到 —— **超时后 server 会自动 reject，Claude 看到 is_error 重试或继续**，UI 上的"已答"状态是 best-effort 显示。

## 数据流 / 接口契约总览

### 协议变更

| 方向 | 类型 | 改动 |
|---|---|---|
| C→S | `answer_question` | **新增** |
| C→S | 其余 | 无变化 |
| S→C | 全部 | 无变化（`tool_use` / `tool_result` 复用现有通道） |

### HTTP 新端点

| 方法 | 路径 | 用途 |
|---|---|---|
| POST | `/upload?cwd=<path>` | multipart 上传附件，返回 `{ path, size }` |

### Dart 新组件 / 文件

| 路径 | 用途 |
|---|---|
| `app/lib/widgets/ask_user_question.dart` | AskUserQuestion 交互渲染（新组件） |
| `app/lib/api/upload_api.dart` | 上传 HTTP 客户端 |

### Server 新文件

| 路径 | 用途 |
|---|---|
| `server/src/upload.ts` | 上传端点 |
| `server/src/ask-user-tool.ts` | AskUserQuestion SDK MCP tool + Registry |

## 错误处理

| 场景 | 行为 |
|---|---|
| 上传超时 / 网络错 | chip 变红 + `!` icon，tap 重试 |
| 上传成功但发送失败 | 文本和路径都保留在 composer，用户重发 |
| AskUserQuestion 30 min 无应答 | server reject Promise，SDK 写 is_error 的 tool_result，Claude 自适应 |
| WS 断线时 client 有未答 question | 重连后该 question 已被 server timeout 或正在 timeout；UI 不需特殊处理（answeredResult 一旦 SDK 写回就会出现） |
| tool_result.content 是无 `text` 字段的 object | `JSON.stringify` 美化 |

## 测试计划

### 手动测试矩阵

| 项 | 测试用例 |
|---|---|
| 按钮 | 亮/暗模式 × {空文本 / 有文本 / busy 中} 三状态截图比对 |
| 附件 | 上传单图 / 多图 / PDF / 5MB 文本 / 25.1MB 文件（应拒）/ 网络断时上传（应失败可重试） |
| 附件 | 上传中按发送（应禁用）/ 上传完按发送（应注入路径） |
| tool 输出 | 让 Claude 调一个返回结构化 JSON 的 MCP 工具，确认显示 pretty JSON |
| AskUserQuestion | 单 Q 单选立即提交 / 单 Q 多选 + 提交 / 双 Q form 模式 / "Other" 自定义 / preview bottom-sheet / 已答态显示 |
| AskUserQuestion | 提交期间断网 → 重连看是否最终一致 |

### 自动化测试

- Server 端：`ask-user-tool.ts` registry 的 register / answer / rejectAll / timeout 单元测试
- Server 端：`serialize.ts` 修复后的 `normalizeToolResultContent` 输入各种 shape 的快照测试
- Server 端：`/upload` 端点的接受 / 拒绝 / 路径校验 happy-path 集成测试

## 风险与未决

1. **SDK 自定义工具是否会被 Claude 自动选用？** 取决于工具描述质量。我们复刻 cc 的描述应该够。需要在实测中验证 Claude 真的会在合适场景调用 AskUserQuestion。
2. **iOS 后台被系统冻结时 socket 断开**：用户切回 app → 现有的 reconnect 逻辑会重连，但 server 端 pending question 已 timeout 或仍在等。**这不是 Spec A 要解决的问题，留给 Spec B**（多会话/后台运行）。
3. **`file_picker` 在 Android 部分国产 ROM 上权限弹窗体验** —— 已知问题，社区方案是引导用户手动授权；本 spec 不额外处理。

## 实现量估算

| 模块 | 行数 | 时长 |
|---|---|---|
| §1 按钮黑白风 | ~50 Flutter | 30 min |
| §2 附件上传 | ~250 Flutter + 80 TS | 4-6 hr |
| §3 tool JSON 修复 | ~15 TS | 15 min |
| §4 AskUserQuestion | ~400 Flutter + 200 TS | 6-8 hr |
| **合计** | **~600 Flutter + ~300 TS** | **~2 工作日** |

## 验收

- [ ] 亮/暗模式下发送 / 停止按钮均匀显示，触感符合规格
- [ ] 上传功能 4 种文件类型可用，进度可见，发送时自动注入路径
- [ ] 任意结构化 tool_result 显示为美化 JSON，不再出现 `[object Object]`
- [ ] Claude 主动调用 AskUserQuestion 时弹出交互表单，单选 tap 即提交，多选/多问走提交按钮，preview tap 弹底部 sheet，已答态显示用户选择
- [ ] 所有改动通过 `flutter analyze` 和 `pnpm -F server build` 无 error
- [ ] 实测一遍完整使用流：开会话 → 上传图 → Claude 答 → 触发 AskUserQuestion → 选 → Claude 继续
