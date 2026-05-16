import {
  deleteSession,
  forkSession,
  getSessionInfo,
  getSessionMessages,
  listSessions,
  renameSession,
  tagSession,
  type SDKSessionInfo,
  type SessionMessage,
} from '@anthropic-ai/claude-agent-sdk';
import type { FastifyInstance } from 'fastify';

import type { SessionSummary } from '@cc/shared';

import { isPathAllowed } from './config.js';
import { messageToWire } from './serialize.js';

function requirePath(cwd: string | undefined): string {
  if (!cwd) throw new Error('missing cwd');
  if (!isPathAllowed(cwd)) throw new Error(`Path not allowed: ${cwd}`);
  return cwd;
}

function toSummary(s: SDKSessionInfo): SessionSummary {
  return {
    session_id: s.sessionId,
    summary: s.summary ?? s.firstPrompt ?? null,
    title: s.customTitle ?? null,
    tags: s.tag ? [s.tag] : [],
    last_modified: s.lastModified ?? null,
    cwd: s.cwd ?? null,
    num_messages: null,
    total_cost_usd: null,
  };
}

export async function registerSessionsApi(app: FastifyInstance): Promise<void> {
  /**
   * List sessions for a given working directory.
   * The SDK returns all sessions globally (the `dir` filter is loose), so we
   * filter strictly to sessions whose cwd matches the requested path.
   */
  app.get<{
    Querystring: { cwd: string; limit?: string; offset?: string; include_subdirs?: string };
  }>('/sessions', async (req) => {
    const cwd = requirePath(req.query.cwd);
    const limit = req.query.limit ? Number(req.query.limit) : 200;
    const offset = req.query.offset ? Number(req.query.offset) : 0;
    const includeSubdirs = req.query.include_subdirs === 'true';

    const all = await listSessions({ dir: cwd, limit: 1000, offset: 0 });
    const filtered = all.filter((s) => {
      const sCwd = s.cwd ?? '';
      if (!sCwd) return false;
      if (sCwd === cwd) return true;
      if (includeSubdirs && sCwd.startsWith(cwd + '/')) return true;
      return false;
    });
    return filtered.slice(offset, offset + limit).map(toSummary);
  });

  app.get<{ Params: { id: string }; Querystring: { cwd: string } }>(
    '/sessions/:id',
    async (req, reply) => {
      const cwd = requirePath(req.query.cwd);
      const info = await getSessionInfo(req.params.id, { dir: cwd });
      if (!info) {
        reply.code(404);
        return { detail: 'Session not found' };
      }
      return info;
    },
  );

  app.get<{
    Params: { id: string };
    Querystring: { cwd: string; limit?: string; offset?: string };
  }>('/sessions/:id/messages', async (req) => {
    const cwd = requirePath(req.query.cwd);
    const limit = req.query.limit ? Number(req.query.limit) : 200;
    const offset = req.query.offset ? Number(req.query.offset) : 0;
    const msgs: SessionMessage[] = await getSessionMessages(req.params.id, {
      dir: cwd,
      limit,
      offset,
    });
    return {
      messages: msgs.map((sm) => {
        const rawTs = (sm as { timestamp?: string | number }).timestamp;
        // JSONL persists ISO strings; live SDK objects use epoch ms.
        const ts =
          typeof rawTs === 'string' ? Date.parse(rawTs) :
          typeof rawTs === 'number' ? rawTs :
          null;
        const wire = messageToWire(sm);
        return {
          uuid: (sm as { uuid?: string }).uuid ?? null,
          parent_uuid: (sm as { parent_uuid?: string }).parent_uuid ?? null,
          timestamp: ts,
          // Embed timestamp into the message itself so client doesn't have to thread it.
          message: wire ? { ...wire, timestamp: ts ?? undefined } : sm,
        };
      }),
    };
  });

  app.post<{
    Params: { id: string };
    Querystring: { cwd: string; title: string };
  }>('/sessions/:id/rename', async (req) => {
    const cwd = requirePath(req.query.cwd);
    await renameSession(req.params.id, req.query.title, { dir: cwd });
    return { ok: true };
  });

  app.post<{
    Params: { id: string };
    Querystring: { cwd: string; tag: string };
  }>('/sessions/:id/tag', async (req) => {
    const cwd = requirePath(req.query.cwd);
    await tagSession(req.params.id, req.query.tag, { dir: cwd });
    return { ok: true };
  });

  app.post<{
    Params: { id: string };
    Querystring: { cwd: string; title?: string };
  }>('/sessions/:id/fork', async (req) => {
    const cwd = requirePath(req.query.cwd);
    const result = await forkSession(req.params.id, {
      dir: cwd,
      ...(req.query.title ? { title: req.query.title } : {}),
    });
    return result;
  });

  app.delete<{ Params: { id: string }; Querystring: { cwd: string } }>(
    '/sessions/:id',
    async (req) => {
      const cwd = requirePath(req.query.cwd);
      await deleteSession(req.params.id, { dir: cwd });
      return { ok: true };
    },
  );
}
