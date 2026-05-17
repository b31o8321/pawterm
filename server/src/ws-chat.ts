import { resolve } from 'node:path';

import type { WebSocket } from '@fastify/websocket';
import type { FastifyRequest } from 'fastify';

import type { ChatClientMessage, ChatServerMessage } from '@cc/shared';

import { isPathAllowed, settings } from './config.js';
import { messageToWire } from './serialize.js';
import { ChatSession } from './session-manager.js';

/**
 * 一个 ManagedSession 跨 ws 连接存活：客户端进/退/重进同一会话时，复用同一个
 * SDK session，把流式输出 fan-out 给当前的订阅 socket。
 *
 * 退出场景对应的行为：
 *   - app 后台 / 退出 → ws close → 取消订阅，但 session 继续跑（CLI 子进程不死）
 *   - 重进来 → ws connect (相同 key) → attach 现有 session，replay 当前轮缓存
 *   - 真正终止 → forceClose（用户长按 stop 或显式 end）
 *
 * key = "${cwd}|${resume_id ?? 'new'}" —— 没 resume 的新会话每次都新建。
 */
interface ManagedSession {
  key: string;
  session: ChatSession;
  /** 当前未完结 turn 的事件流缓存（result 到达后清空，等下一轮）。 */
  outputBuffer: ChatServerMessage[];
  /** 当前活跃的订阅 socket（最多 1 个；新连接接管旧的）。 */
  subscriber: WebSocket | null;
  busy: boolean;
  /** subscriber=null 后用于"N 秒没人接管就 close"的兜底定时器。 */
  idleCloseTimer: NodeJS.Timeout | null;
}

const sessions = new Map<string, ManagedSession>();

/** 没人订阅多久后自动关掉 session — 防止悬空 SDK 子进程堆积。 */
const IDLE_CLOSE_MS = 5 * 60 * 1000;

/** outputBuffer 上限，避免极长 turn 把内存撑爆。 */
const OUTPUT_BUFFER_MAX = 4000;

function sessionKey(cwd: string, resume?: string | null): string {
  return `${cwd}|${resume ?? 'new'}`;
}

function broadcast(m: ManagedSession, payload: ChatServerMessage): void {
  const s = m.subscriber;
  if (s && s.readyState === 1) {
    try { s.send(JSON.stringify(payload)); } catch { /* ignore */ }
  }
}

export function handleChatSocket(socket: WebSocket, _req: FastifyRequest): void {
  let attached: ManagedSession | null = null;

  function sendDirect(payload: ChatServerMessage): void {
    if (socket.readyState !== 1) return;
    try { socket.send(JSON.stringify(payload)); } catch { /* ignore */ }
  }

  async function streamResponses(m: ManagedSession, iter: AsyncIterableIterator<any>): Promise<void> {
    try {
      for await (const sdkMsg of iter) {
        const wire = messageToWire(sdkMsg);
        if (!wire) continue;
        const stamped = { ...wire, timestamp: Date.now() } as ChatServerMessage;
        const type = (stamped as any).type;
        // 维护 busy 状态
        if (type === 'result' || type === 'error') {
          m.busy = false;
          // 一个 turn 结束就把缓存清掉，重连只 replay 当前 turn 的进度
          m.outputBuffer.length = 0;
        } else {
          m.outputBuffer.push(stamped);
          if (m.outputBuffer.length > OUTPUT_BUFFER_MAX) {
            // 超过上限就丢早期事件（最早期一般是 stream_block_start/delta 序列）
            m.outputBuffer.splice(0, m.outputBuffer.length - OUTPUT_BUFFER_MAX);
          }
          if (type === 'user_message' || type === 'assistant' || type === 'stream_block_start') {
            m.busy = true;
          }
        }
        broadcast(m, stamped);
      }
    } catch (err) {
      const e = err as Error;
      broadcast(m, { type: 'error', message: `stream error: ${e.message}` });
      m.busy = false;
    } finally {
      m.busy = false;
    }
  }

  function attach(m: ManagedSession): void {
    // 把旧的 subscriber 踢掉（旧 ws 可能已经关闭、可能还活着——告知它被接管了）
    if (m.subscriber && m.subscriber !== socket && m.subscriber.readyState === 1) {
      try { m.subscriber.close(4100, 'replaced by newer connection'); } catch { /* ignore */ }
    }
    m.subscriber = socket;
    if (m.idleCloseTimer) {
      clearTimeout(m.idleCloseTimer);
      m.idleCloseTimer = null;
    }
    attached = m;
  }

  function detach(reason: 'close' | 'error'): void {
    if (!attached || attached.subscriber !== socket) return;
    attached.subscriber = null;
    // 没在跑就启动空闲计时器，5 分钟后还没人来就 close session
    if (!attached.busy && !attached.idleCloseTimer) {
      const m = attached;
      attached.idleCloseTimer = setTimeout(() => {
        if (sessions.get(m.key) === m && m.subscriber == null) {
          m.session.close();
          sessions.delete(m.key);
        }
      }, IDLE_CLOSE_MS);
    }
    attached = null;
    void reason;
  }

  socket.on('message', (raw: Buffer | string) => {
    let msg: ChatClientMessage;
    try {
      msg = JSON.parse(raw.toString()) as ChatClientMessage;
    } catch {
      sendDirect({ type: 'error', message: 'Invalid JSON' });
      return;
    }

    switch (msg.type) {
      case 'init': {
        const cwd = resolve(msg.cwd);
        if (!isPathAllowed(cwd)) {
          sendDirect({ type: 'error', message: `Project not allowed: ${cwd}` });
          return;
        }
        const permissionMode = msg.permission_mode ?? settings.permissionMode;
        const key = sessionKey(cwd, msg.resume);

        // 1) 尝试 attach 现有 session（同 cwd+resume 之前有连接过）
        const existing = sessions.get(key);
        if (existing) {
          attach(existing);
          sendDirect({
            type: 'session_ready',
            session_key: key,
            cwd,
            permission_mode: permissionMode,
            resumed: msg.resume ?? null,
            busy: existing.busy, // 让客户端立即显示 streaming UI
          });
          // replay 当前 turn 的缓存（让重连客户端看到 in-flight 内容）
          for (const ev of existing.outputBuffer) sendDirect(ev);
          return;
        }

        // 2) 起新 session
        try {
          const session = new ChatSession({ cwd, permissionMode, resume: msg.resume, model: msg.model });
          const m: ManagedSession = {
            key,
            session,
            outputBuffer: [],
            subscriber: socket,
            busy: false,
            idleCloseTimer: null,
          };
          sessions.set(key, m);
          attached = m;
          const iter = session.start();
          sendDirect({
            type: 'session_ready',
            session_key: key,
            cwd,
            permission_mode: permissionMode,
            resumed: msg.resume ?? null,
          });
          streamResponses(m, iter).catch((err) => {
            broadcast(m, { type: 'error', message: `iterator failed: ${(err as Error).message}` });
          });
        } catch (err) {
          sendDirect({ type: 'error', message: `Failed to start session: ${(err as Error).message}` });
        }
        break;
      }

      case 'user_message': {
        if (!attached) {
          sendDirect({ type: 'error', message: 'Session not initialized' });
          return;
        }
        if (attached.busy) {
          // 客户端有自己的 queue；如果还是发过来，就拒绝（约定客户端会排队）
          sendDirect({ type: 'error', message: 'Previous turn still streaming' });
          return;
        }
        attached.busy = true;
        attached.session.pushUserMessage(msg.text);
        break;
      }

      case 'set_model': {
        attached?.session.setModel(msg.model).catch((err) => {
          sendDirect({ type: 'error', message: `setModel failed: ${(err as Error).message}` });
        });
        break;
      }

      case 'set_permission_mode': {
        attached?.session.setPermissionMode(msg.mode).catch((err) => {
          sendDirect({ type: 'error', message: `setPermissionMode failed: ${(err as Error).message}` });
        });
        break;
      }

      case 'interrupt': {
        attached?.session.interrupt().catch(() => {});
        break;
      }

      case 'ping': {
        sendDirect({ type: 'pong' });
        break;
      }
    }
  });

  socket.on('close', () => detach('close'));
  socket.on('error', () => detach('error'));
}
