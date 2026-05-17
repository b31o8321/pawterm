// ============================================================
// AskUserQuestionRegistry
// ============================================================
// Suspends an MCP tool handler until the client answers, then
// resolves with a formatted tool result string.
// ============================================================

type CallToolResult = { content: Array<{ type: 'text'; text: string }> };

type Resolver = (result: CallToolResult) => void;
type Rejecter = (err: Error) => void;

const DEFAULT_TIMEOUT_MS = 30 * 60 * 1000;

export class AskUserQuestionRegistry {
  private pending = new Map<string, { resolve: Resolver; reject: Rejecter; timer: ReturnType<typeof setTimeout> }>();
  private readonly timeoutMs: number;

  constructor(opts: { timeoutMs?: number } = {}) {
    this.timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  }

  register(toolUseId: string): Promise<CallToolResult> {
    return new Promise<CallToolResult>((resolve, reject) => {
      const timer = setTimeout(() => {
        if (this.pending.has(toolUseId)) {
          this.pending.delete(toolUseId);
          reject(new Error(`User did not answer within 30 minutes`));
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
