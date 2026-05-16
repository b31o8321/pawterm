import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

import type { Project, PermissionMode } from '@cc/shared';

const __dirname = dirname(fileURLToPath(import.meta.url));

export interface ServerSettings {
  host: string;
  port: number;
  permissionMode: PermissionMode;
  projects: Project[];
}

function expandHome(p: string): string {
  if (p.startsWith('~/')) return resolve(homedir(), p.slice(2));
  if (p === '~') return homedir();
  return resolve(p);
}

function loadConfig(): ServerSettings {
  const configPath = process.env.CC_CONFIG ?? resolve(__dirname, '..', 'config.json');
  if (!existsSync(configPath)) {
    console.warn(`[config] No config.json at ${configPath} — defaulting to $HOME`);
    return {
      host: '0.0.0.0',
      port: 8765,
      permissionMode: 'acceptEdits',
      projects: [{ name: 'home', path: homedir() }],
    };
  }

  const raw = JSON.parse(readFileSync(configPath, 'utf-8')) as {
    host?: string;
    port?: number;
    permission_mode?: PermissionMode;
    projects?: Array<{ name: string; path: string }>;
  };

  return {
    host: raw.host ?? '0.0.0.0',
    port: raw.port ?? 8765,
    permissionMode: raw.permission_mode ?? 'acceptEdits',
    projects: (raw.projects ?? []).map((p) => ({
      name: p.name,
      path: expandHome(p.path),
    })),
  };
}

export const settings = loadConfig();

/** Returns true if `target` is inside any whitelisted project root. */
export function isPathAllowed(target: string): boolean {
  const t = resolve(target);
  for (const p of settings.projects) {
    const root = resolve(p.path);
    const rel = relative(root, t);
    if (rel === '' || (!rel.startsWith('..') && !resolve(rel).startsWith('..'))) {
      return true;
    }
  }
  return false;
}
