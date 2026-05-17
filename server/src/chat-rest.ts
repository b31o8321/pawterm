import type { FastifyInstance } from 'fastify';
import { resolve } from 'node:path';
import { getSessionInfo } from '@anthropic-ai/claude-agent-sdk';

import type { AnswerQuestionRequest, PermissionMode } from '@cc/shared';

import { isPathAllowed, settings } from './config.js';
import { AskUserQuestionRegistry } from './ask-user-tool.js';
import { EventBuffer } from './event-buffer.js';
import { findHolder } from './holder-detect.js';
import { messageToWire } from './serialize.js';
import { ChatSession } from './session-manager.js';

interface RunEntry {
  session: ChatSession;
  buffer: EventBuffer;
  askRegistry: AskUserQuestionRegistry;
  /** Grace timer: starts when result arrives, clears run after GRACE_MS. */
  graceTimer?: NodeJS.Timeout;
  writers: Set<{ write: (s: string) => void; end: () => void }>;
  /** True once a result event has been emitted for this turn. */
  resultReceived: boolean;
}

/** Key = Claude UUID (same as jsonl filename). Only present during an active turn. */
const activeRuns = new Map<string, RunEntry>();
const GRACE_MS = 60_000;
const HEARTBEAT_MS = 15_000;

function broadcast(entry: RunEntry, type: string, data: unknown): void {
  const ev = entry.buffer.push(type, data);
  const payload = `id: ${ev.id}\nevent: ${type}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const w of [...entry.writers]) {
    try {
      w.write(payload);
    } catch {
      entry.writers.delete(w);
    }
  }
}

function cancelGrace(entry: RunEntry): void {
  if (entry.graceTimer) {
    clearTimeout(entry.graceTimer);
    entry.graceTimer = undefined;
  }
}

function startGrace(uuid: string, entry: RunEntry): void {
  if (entry.graceTimer) return;
  entry.graceTimer = setTimeout(() => {
    closeRun(uuid);
  }, GRACE_MS);
}

function closeRun(uuid: string): void {
  const entry = activeRuns.get(uuid);
  if (!entry) return;
  cancelGrace(entry);
  entry.askRegistry.rejectAll('run closed');
  // Interrupt first so the SDK subprocess actually stops, then close input gen.
  entry.session.interrupt().finally(() => {
    entry.session.close();
  });
  for (const w of entry.writers) {
    try { w.end(); } catch { /* */ }
  }
  activeRuns.delete(uuid);
}

const ASK_TOOL_NAME = 'mcp__ask-user-question__AskUserQuestion';

function maybeSetPendingToolUseId(wire: ReturnType<typeof messageToWire>, registry: AskUserQuestionRegistry): void {
  if (!wire || wire.type !== 'assistant') return;
  const content = (wire as { content?: unknown[] }).content;
  if (!Array.isArray(content)) return;
  for (const block of content) {
    if (
      block && typeof block === 'object' &&
      (block as { type?: string }).type === 'tool_use' &&
      (block as { name?: string }).name === ASK_TOOL_NAME
    ) {
      registry.pendingToolUseId = (block as { id?: string }).id ?? null;
      return;
    }
  }
}

async function consumeSdk(uuid: string, entry: RunEntry): Promise<void> {
  try {
    const iter = entry.session.start();
    for await (const sdkMsg of iter) {
      const wire = messageToWire(sdkMsg);
      if (wire) {
        const stamped = { ...wire, timestamp: Date.now() };
        maybeSetPendingToolUseId(wire, entry.askRegistry);
        broadcast(entry, (wire as { type: string }).type, stamped);
        // When result arrives: mark it and start grace timer.
        // The run stays in activeRuns during grace so reconnects can replay.
        if ((wire as { type: string }).type === 'result') {
          entry.resultReceived = true;
          startGrace(uuid, entry);
        }
      }
    }
  } catch (err) {
    broadcast(entry, 'error', { type: 'error', message: (err as Error).message });
    entry.resultReceived = true;
    startGrace(uuid, entry);
  } finally {
    // If consumeSdk ends without a result (e.g. session.close() called before
    // SDK emitted result), make sure grace starts so we don't leak the entry.
    if (!entry.resultReceived) {
      entry.resultReceived = true;
      startGrace(uuid, entry);
    }
  }
}

export async function registerChatRest(app: FastifyInstance): Promise<void> {
  /**
   * Start a new turn. Creates a fresh RunEntry for the given Claude UUID.
   *
   * Body: { cwd, text, model?, permission_mode? }
   *
   * - If uuid already has an active run → 409
   * - If session exists on disk (getSessionInfo finds it) → resume: uuid
   * - If not → sessionId: uuid  (new session with client-provided UUID)
   */
  app.post<{
    Params: { uuid: string };
    Body: { cwd?: string; text?: string; model?: string; permission_mode?: PermissionMode };
  }>(
    '/chat/:uuid/turn',
    async (req, reply) => {
      const { uuid } = req.params;
      const body = req.body ?? {};

      if (!body.cwd) { reply.code(400); return { error: 'cwd required' }; }
      if (!body.text) { reply.code(400); return { error: 'text required' }; }

      const cwd = resolve(body.cwd);
      if (!isPathAllowed(cwd)) { reply.code(403); return { error: `Project not allowed: ${cwd}` }; }

      if (activeRuns.has(uuid)) {
        reply.code(409);
        return { error: 'turn already active for this session' };
      }

      const permissionMode = body.permission_mode ?? settings.permissionMode;

      // Determine whether to resume or create new.
      const existing = await getSessionInfo(uuid, { dir: cwd });
      const askRegistry = new AskUserQuestionRegistry();
      const session = new ChatSession({
        cwd,
        permissionMode,
        ...(existing ? { resume: uuid } : { sessionId: uuid }),
        model: body.model,
        askRegistry,
      });

      const entry: RunEntry = {
        session,
        buffer: new EventBuffer(2000),   // larger buffer for long runs
        askRegistry,
        writers: new Set(),
        resultReceived: false,
      };
      activeRuns.set(uuid, entry);

      // Push the user message then start consuming.
      session.pushUserMessage(body.text);
      consumeSdk(uuid, entry).catch(() => {});

      return { ok: true };
    },
  );

  app.get<{ Params: { uuid: string }; Querystring: { lastEventId?: string } }>(
    '/chat/:uuid/events',
    (req, reply) => {
      const { uuid } = req.params;
      const entry = activeRuns.get(uuid);
      if (!entry) { reply.code(404); return reply.send({ error: 'no active turn' }); }

      const lastIdHeader = (req.headers['last-event-id'] as string | undefined) ?? req.query.lastEventId;
      const lastId = lastIdHeader ? parseInt(lastIdHeader, 10) : 0;
      if (lastId > 0) {
        const probe = entry.buffer.since(lastId);
        if (probe === null) { reply.code(412); return reply.send({ error: 'event gap, please reload' }); }
      }

      reply.hijack();
      reply.raw.setHeader('Content-Type', 'text/event-stream');
      reply.raw.setHeader('Cache-Control', 'no-cache');
      reply.raw.setHeader('Connection', 'keep-alive');
      reply.raw.flushHeaders();

      const writer = {
        write: (s: string) => reply.raw.write(s),
        end: () => reply.raw.end(),
      };
      entry.writers.add(writer);

      // Replay missed events.
      if (lastId > 0) {
        const replay = entry.buffer.since(lastId) ?? [];
        for (const e of replay) {
          writer.write(`id: ${e.id}\nevent: ${e.type}\ndata: ${JSON.stringify(e.data)}\n\n`);
        }
      } else if (lastId === 0 && entry.buffer.newestId > 0) {
        // New subscriber: replay all buffered events from this turn.
        const all = entry.buffer.since(0) ?? [];
        for (const e of all) {
          writer.write(`id: ${e.id}\nevent: ${e.type}\ndata: ${JSON.stringify(e.data)}\n\n`);
        }
      }

      const heartbeat = setInterval(() => {
        try {
          writer.write(`: heartbeat\n\n`);
        } catch {
          entry.writers.delete(writer);
          clearInterval(heartbeat);
        }
      }, HEARTBEAT_MS);

      req.raw.on('close', () => {
        clearInterval(heartbeat);
        entry.writers.delete(writer);
        // NOTE: disconnecting does NOT trigger grace. Grace only starts on result.
      });

      return reply;
    },
  );

  /**
   * GET /chat/:uuid/status — three-signal turn state.
   * 'live'    → activeRuns has entry, result not yet received
   * 'done'    → activeRuns has entry but result already received (in grace)
   * 'running' → no activeRun but PID holder found
   * 'unknown' → no activeRun and no holder
   */
  app.get<{ Params: { uuid: string }; Querystring: { cwd?: string } }>(
    '/chat/:uuid/status',
    async (req) => {
      const { uuid } = req.params;
      const entry = activeRuns.get(uuid);
      if (entry) {
        return { state: entry.resultReceived ? 'done' : 'live' };
      }
      // Check PID holder as secondary signal.
      const holder = await findHolder(uuid).catch(() => null);
      if (holder) {
        return { state: 'running', holder };
      }
      return { state: 'unknown' };
    },
  );

  app.post<{ Params: { uuid: string } }>('/chat/:uuid/interrupt', async (req, reply) => {
    const entry = activeRuns.get(req.params.uuid);
    if (!entry) { reply.code(404); return { error: 'no active turn' }; }
    await entry.session.interrupt();
    return { ok: true };
  });

  app.post<{ Params: { uuid: string }; Body: { model: string } }>(
    '/chat/:uuid/set-model',
    async (req, reply) => {
      const entry = activeRuns.get(req.params.uuid);
      if (!entry) { reply.code(404); return { error: 'no active turn' }; }
      await entry.session.setModel(req.body.model);
      return { ok: true };
    },
  );

  app.post<{ Params: { uuid: string }; Body: { mode: PermissionMode } }>(
    '/chat/:uuid/set-permission-mode',
    async (req, reply) => {
      const entry = activeRuns.get(req.params.uuid);
      if (!entry) { reply.code(404); return { error: 'no active turn' }; }
      await entry.session.setPermissionMode(req.body.mode);
      return { ok: true };
    },
  );

  app.post<{ Params: { uuid: string }; Body: AnswerQuestionRequest }>(
    '/chat/:uuid/answer-question',
    async (req, reply) => {
      const entry = activeRuns.get(req.params.uuid);
      if (!entry) { reply.code(404); return { error: 'no active turn' }; }
      const ok = entry.session.answerQuestion(
        req.body.tool_use_id,
        req.body.answers,
        req.body.annotations,
      );
      if (!ok) {
        app.log.warn({ toolUseId: req.body.tool_use_id }, 'answer_question: no pending tool');
      }
      return { ok };
    },
  );

  app.delete<{ Params: { uuid: string } }>('/chat/:uuid', async (req) => {
    closeRun(req.params.uuid);
    return { ok: true };
  });
}

/** Exported for AskUserQuestion wiring. */
export function getRunEntry(uuid: string): RunEntry | undefined {
  return activeRuns.get(uuid);
}

/**
 * @deprecated Use getRunEntry. Kept for backward compat with ask-user-tool.ts
 * which may reference getSessionEntry.
 */
export const getSessionEntry = getRunEntry;
