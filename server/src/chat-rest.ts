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
  // Snapshot to avoid mutation-during-iteration when we prune dead writers.
  for (const w of [...entry.writers]) {
    try {
      w.write(payload);
    } catch {
      entry.writers.delete(w);
    }
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
        broadcast(entry, (wire as { type: string }).type, stamped);
      }
    }
  } catch (err) {
    broadcast(entry, 'error', { type: 'error', message: (err as Error).message });
  } finally {
    // SDK iterator ended (naturally or via error). Tear down so reconnects
    // get a fresh 404 rather than a session that silently ignores messages.
    closeSession(id);
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
      // Startup grace: if the client never opens /chat/:id/events, tear the
      // session down after GRACE_MS. The first SSE connect cancels this.
      startGrace(id, entry);
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

      if (lastId > 0) {
        const replay = entry.buffer.since(lastId) ?? [];
        for (const e of replay) {
          writer.write(`id: ${e.id}\nevent: ${e.type}\ndata: ${JSON.stringify(e.data)}\n\n`);
        }
      }

      const heartbeat = setInterval(() => {
        try {
          writer.write(`: heartbeat\n\n`);
        } catch {
          // Writer dead; clean up. The 'close' handler will also run, but make this idempotent.
          entry.writers.delete(writer);
          clearInterval(heartbeat);
          if (entry.writers.size === 0) {
            startGrace(id, entry);
          }
        }
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
