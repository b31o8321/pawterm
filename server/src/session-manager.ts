import { query, type Options } from '@anthropic-ai/claude-agent-sdk';

import type { PermissionMode } from '@cc/shared';

/**
 * One ClaudeSDK conversation. We use the SDK's streaming `query()` with an
 * input async generator so we can feed user messages over the lifetime of
 * a single WebSocket.
 */
export class ChatSession {
  readonly cwd: string;
  readonly permissionMode: PermissionMode;
  readonly resume?: string;
  readonly model?: string;

  private inputResolver?: (msg: any) => void;
  private inputQueue: any[] = [];
  private finished = false;
  private iter?: AsyncGenerator<any>;

  constructor(opts: { cwd: string; permissionMode: PermissionMode; resume?: string; model?: string }) {
    this.cwd = opts.cwd;
    this.permissionMode = opts.permissionMode;
    this.resume = opts.resume;
    this.model = opts.model;
  }

  /** Build the async iterator the SDK will read user messages from. */
  private inputGen = async function* (this: ChatSession): AsyncGenerator<any> {
    while (!this.finished) {
      if (this.inputQueue.length > 0) {
        yield this.inputQueue.shift();
        continue;
      }
      const next = await new Promise<any>((resolve) => {
        this.inputResolver = resolve;
      });
      this.inputResolver = undefined;
      if (next === null) return; // stop signal
      yield next;
    }
  };

  start(): AsyncIterableIterator<any> {
    const options: Options = {
      cwd: this.cwd,
      permissionMode: this.permissionMode,
      // Emit SDKPartialAssistantMessage events for char-level streaming.
      includePartialMessages: true,
      ...(this.resume ? { resume: this.resume } : {}),
      ...(this.model ? { model: this.model } : {}),
    };
    this.iter = query({ prompt: this.inputGen.call(this), options });
    return this.iter as unknown as AsyncIterableIterator<any>;
  }

  /** Runtime model switch — SDK supports this via setModel on the iterator. */
  async setModel(model: string): Promise<void> {
    const iter = this.iter as any;
    if (iter?.setModel) {
      await iter.setModel(model);
    }
  }

  pushUserMessage(text: string): void {
    const msg = {
      type: 'user',
      message: { role: 'user', content: text },
      parent_tool_use_id: null,
      session_id: '',
    };
    if (this.inputResolver) {
      this.inputResolver(msg);
    } else {
      this.inputQueue.push(msg);
    }
  }

  async interrupt(): Promise<void> {
    if (this.iter && (this.iter as any).interrupt) {
      await (this.iter as any).interrupt();
    }
  }

  close(): void {
    this.finished = true;
    if (this.inputResolver) {
      this.inputResolver(null);
    }
  }
}
