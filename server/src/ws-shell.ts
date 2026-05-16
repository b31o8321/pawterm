import { existsSync, statSync } from 'node:fs';
import { resolve } from 'node:path';

import type { WebSocket } from '@fastify/websocket';
import type { FastifyRequest } from 'fastify';
import * as pty from 'node-pty';

import type { ShellClientMessage, ShellServerMessage } from '@cc/shared';

import { isPathAllowed } from './config.js';

/**
 * Pick a usable login shell. Order:
 *   1. msg.shell from client (if exists)
 *   2. $SHELL env (if exists)
 *   3. /bin/zsh → /bin/bash → /bin/sh
 */
function pickShell(requested: string | undefined): string {
  const candidates = [
    requested,
    process.env.SHELL,
    '/bin/zsh',
    '/bin/bash',
    '/bin/sh',
  ];
  for (const c of candidates) {
    if (c && existsSync(c)) return c;
  }
  // Fallback: return /bin/sh even if not found; spawn will produce a clear error.
  return '/bin/sh';
}

/**
 * Defense in depth — if a client opens /ws/shell but doesn't send `init`
 * within this many ms, we close the socket. Prevents abandoned sockets
 * from sitting around and (combined with future spawn) leaking PTYs.
 */
const INIT_TIMEOUT_MS = 10_000;

export function handleShellSocket(socket: WebSocket, _req: FastifyRequest): void {
  let term: pty.IPty | null = null;
  let initialized = false;

  const initWatchdog = setTimeout(() => {
    if (!initialized) {
      try {
        socket.close(4000, 'init timeout');
      } catch {
        /* ignore */
      }
    }
  }, INIT_TIMEOUT_MS);

  function send(payload: ShellServerMessage): void {
    if (socket.readyState !== 1) return;
    socket.send(JSON.stringify(payload));
  }

  function teardown(): void {
    clearTimeout(initWatchdog);
    if (term) {
      try {
        term.kill('SIGKILL');
      } catch {
        /* ignore */
      }
      term = null;
    }
  }

  function spawnPty(cwd: string, shell: string, cols: number, rows: number): pty.IPty {
    return pty.spawn(shell, ['-l'], {
      name: 'xterm-256color',
      cols,
      rows,
      cwd,
      env: {
        ...process.env,
        TERM: 'xterm-256color',
        COLORTERM: 'truecolor',
        FORCE_COLOR: '3',
        LANG: process.env.LANG ?? 'en_US.UTF-8',
      },
    });
  }

  socket.on('message', (raw: Buffer | string) => {
    let msg: ShellClientMessage;
    try {
      msg = JSON.parse(raw.toString()) as ShellClientMessage;
    } catch {
      send({ type: 'error', message: 'Invalid JSON' });
      return;
    }

    switch (msg.type) {
      case 'init': {
        if (initialized) {
          send({ type: 'error', message: 'Already initialized; open a new socket to re-init' });
          return;
        }
        const cwd = resolve(msg.cwd);
        if (!isPathAllowed(cwd)) {
          send({ type: 'error', message: `Project not allowed: ${cwd}` });
          try { socket.close(4001, 'forbidden cwd'); } catch { /* ignore */ }
          return;
        }
        // 校验 cwd 是真实存在的目录，否则 pty.spawn 会以 ENOENT 失败，
        // 错误消息又非常隐晦（"spawn failed: posix_spawnp failed"）。
        if (!existsSync(cwd) || !statSync(cwd).isDirectory()) {
          send({ type: 'error', message: `cwd not a directory: ${cwd}` });
          try { socket.close(4003, 'bad cwd'); } catch { /* ignore */ }
          return;
        }
        initialized = true;
        clearTimeout(initWatchdog);
        const shell = pickShell(msg.shell);
        try {
          term = spawnPty(cwd, shell, msg.cols, msg.rows);
          term.onData((data) => send({ type: 'output', data }));
          term.onExit(({ exitCode }) => {
            send({ type: 'exit', code: exitCode });
            term = null;
          });
          send({ type: 'ready' });
        } catch (err) {
          const e = err as NodeJS.ErrnoException;
          const detail = [e.code, e.message].filter(Boolean).join(' · ');
          send({
            type: 'error',
            message: `spawn failed [shell=${shell} cwd=${cwd}] ${detail}`,
          });
          try { socket.close(4002, 'spawn failed'); } catch { /* ignore */ }
        }
        break;
      }

      case 'input':
        term?.write(msg.data);
        break;

      case 'resize':
        try {
          term?.resize(msg.cols, msg.rows);
        } catch {
          /* ignore */
        }
        break;

      case 'signal':
        term?.kill(msg.signal);
        break;
    }
  });

  socket.on('close', teardown);
  socket.on('error', teardown);
}
