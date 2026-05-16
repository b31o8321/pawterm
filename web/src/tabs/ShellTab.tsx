import '@xterm/xterm/css/xterm.css';

import { FitAddon } from '@xterm/addon-fit';
import { WebLinksAddon } from '@xterm/addon-web-links';
import { Terminal } from '@xterm/xterm';
import { useEffect, useRef } from 'react';

import { useShellSocket } from '../api/wsShell';
import { useAppStore } from '../state/store';

export function ShellTab() {
  const session = useAppStore((s) => s.currentSession);
  const ref = useRef<HTMLDivElement | null>(null);
  const termRef = useRef<Terminal | null>(null);
  const fitRef = useRef<FitAddon | null>(null);

  useEffect(() => {
    if (!ref.current || !session) return;

    const term = new Terminal({
      fontFamily: [
        // Users who installed a Nerd Font get everything from one font (best)
        '"JetBrainsMono Nerd Font"',
        '"MesloLGS NF"',
        '"FiraCode Nerd Font"',
        '"Hack Nerd Font"',
        '"CaskaydiaCove Nerd Font"',
        // Common monospace fonts for text glyphs
        '"JetBrains Mono"',
        '"Fira Code"',
        '"SF Mono"',
        'Menlo',
        'Consolas',
        // Bundled fallback: provides Nerd Font icons for everyone else
        '"Symbols Nerd Font Mono"',
        'monospace',
      ].join(', '),
      fontSize: 13,
      cursorBlink: true,
      theme: {
        background: '#0B1210',
        foreground: '#E6E6E6',
        cursor: '#10B981',
        cursorAccent: '#10B981',
        selectionBackground: '#10B98155',
        black: '#000000',
        white: '#FFFFFF',
        red: '#E06C75',
        green: '#7BD88F',
        yellow: '#E5C07B',
        blue: '#61AFEF',
        magenta: '#C678DD',
        cyan: '#56B6C2',
        brightBlack: '#5C6370',
        brightRed: '#E06C75',
        brightGreen: '#7BD88F',
        brightYellow: '#E5C07B',
        brightBlue: '#61AFEF',
        brightMagenta: '#C678DD',
        brightCyan: '#56B6C2',
        brightWhite: '#FFFFFF',
      },
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.loadAddon(new WebLinksAddon());
    term.open(ref.current);
    fit.fit();
    termRef.current = term;
    fitRef.current = fit;

    const ro = new ResizeObserver(() => {
      try {
        fit.fit();
      } catch {}
    });
    ro.observe(ref.current);

    return () => {
      ro.disconnect();
      term.dispose();
      termRef.current = null;
      fitRef.current = null;
    };
  }, [session?.cwd]);

  const cols = termRef.current?.cols ?? 80;
  const rows = termRef.current?.rows ?? 24;

  const ws = useShellSocket({
    cwd: session?.cwd ?? '',
    cols,
    rows,
    enabled: !!session && !!termRef.current,
    onData: (data) => termRef.current?.write(data),
    onExit: (code) => termRef.current?.write(`\r\n\x1b[33m[process exited ${code}]\x1b[0m\r\n`),
  });

  useEffect(() => {
    if (!termRef.current) return;
    const disp = termRef.current.onData((data) => ws.sendInput(data));
    const dispResize = termRef.current.onResize(({ cols, rows }) => ws.resize(cols, rows));
    return () => {
      disp.dispose();
      dispResize.dispose();
    };
  }, [ws]);

  if (!session) {
    return (
      <div className="flex-1 grid place-items-center text-center text-dim text-xs">
        从左侧选择项目
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col min-h-0">
      {ws.error && (
        <div className="px-4 py-2 bg-red-500/10 border-b border-red-500/30 text-red-300 text-xs">
          {ws.error}
        </div>
      )}
      <div ref={ref} className="flex-1 bg-[#0B1210] p-2 overflow-hidden" />
    </div>
  );
}
