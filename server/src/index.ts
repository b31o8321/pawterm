import cors from '@fastify/cors';
import websocketPlugin from '@fastify/websocket';
import Fastify from 'fastify';
import { mkdir, readdir } from 'node:fs/promises';
import { hostname, homedir } from 'node:os';
import { resolve } from 'node:path';

import type { HealthResponse, Project } from '@cc/shared';

import { settings, addProject, removeProject, ProjectExistsError } from './config.js';
import { buildLoggerOptions } from './logger.js';
import { registerSessionsApi } from './sessions-api.js';
import { handleChatSocket } from './ws-chat.js';
import { handleShellSocket } from './ws-shell.js';

const VERSION = '0.2.0';

async function main(): Promise<void> {
  const app = Fastify({ logger: buildLoggerOptions() });

  await app.register(cors, { origin: true });
  await app.register(websocketPlugin);

  // REST: health
  app.get('/health', async (): Promise<HealthResponse> => ({ status: 'ok', version: VERSION, hostname: hostname() }));

  // REST: projects list
  app.get('/projects', async (): Promise<Project[]> => settings.projects);

  // REST: add project. name is optional; defaults to basename(path).
  app.post<{ Body: { name?: string; path: string } }>('/projects', async (req, reply) => {
    const { name, path: p } = req.body ?? {};
    if (!p) {
      reply.code(400);
      return { error: 'path required' };
    }
    try {
      return await addProject(name, p);
    } catch (err) {
      if (err instanceof ProjectExistsError) {
        reply.code(409);
        return { error: 'duplicate', path: err.path, message: '该目录已在项目列表中' };
      }
      throw err;
    }
  });

  // REST: remove project (config only — never touches ~/.claude/projects sessions).
  app.delete<{ Querystring: { path?: string } }>('/projects', async (req, reply) => {
    const p = req.query.path;
    if (!p) {
      reply.code(400);
      return { error: 'path required' };
    }
    const removed = await removeProject(p);
    if (!removed) reply.code(404);
    return { removed };
  });

  // REST: browse server filesystem (directories only)
  app.get<{ Querystring: { path?: string } }>('/browse', async (req): Promise<{ dirs: string[] }> => {
    const p = req.query.path;
    const abs = p ? resolve(p.replace(/^~/, homedir())) : homedir();
    try {
      const entries = await readdir(abs, { withFileTypes: true });
      const dirs = entries
        .filter((e) => e.isDirectory() && !e.name.startsWith('.'))
        .map((e) => `${abs}/${e.name}`)
        .sort();
      return { dirs };
    } catch {
      return { dirs: [] };
    }
  });

  // REST: create a new subdirectory under `parent`.
  app.post<{ Body: { parent: string; name: string } }>('/browse/mkdir', async (req, reply) => {
    const { parent, name } = req.body ?? {};
    if (!parent || !name) {
      reply.code(400);
      return { error: 'parent and name required' };
    }
    const safeName = name.replace(/[\/\\]/g, '').trim();
    if (!safeName || safeName === '.' || safeName === '..') {
      reply.code(400);
      return { error: 'invalid name' };
    }
    const abs = resolve(parent.replace(/^~/, homedir()), safeName);
    try {
      await mkdir(abs);
      return { path: abs };
    } catch (err) {
      const e = err as NodeJS.ErrnoException;
      if (e.code === 'EEXIST') {
        reply.code(409);
        return { error: 'exists', path: abs };
      }
      reply.code(500);
      return { error: e.message };
    }
  });

  // REST: sessions
  await registerSessionsApi(app);

  // WebSocket: chat
  app.get('/ws/session', { websocket: true }, (socket, req) => {
    handleChatSocket(socket, req);
  });

  // WebSocket: shell
  app.get('/ws/shell', { websocket: true }, (socket, req) => {
    handleShellSocket(socket, req);
  });

  await app.listen({ host: settings.host, port: settings.port });
  app.log.info(`Claude Companion server v${VERSION} on http://${settings.host}:${settings.port}`);
  app.log.info(`Projects: ${settings.projects.map((p) => p.name).join(', ') || '(none)'}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
