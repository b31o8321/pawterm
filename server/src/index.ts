import cors from '@fastify/cors';
import websocketPlugin from '@fastify/websocket';
import Fastify from 'fastify';
import { hostname } from 'node:os';

import type { HealthResponse, Project } from '@cc/shared';

import { settings } from './config.js';
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

  // REST: projects
  app.get('/projects', async (): Promise<Project[]> => settings.projects);

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
