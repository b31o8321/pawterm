import { ArrowUp, AtSign, Paperclip, StopCircle } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';

import { useChatSocket, type ChatTurn } from '../api/wsChat';
import {
  AssistantMessage,
  ErrorLine,
  LocalUserMessage,
  ResultLine,
  UserToolResults,
} from '../components/MessageView';
import { useAppStore } from '../state/store';

export function ChatTab() {
  const session = useAppStore((s) => s.currentSession);
  const enabled = !!session;
  const cwd = session?.cwd ?? '';
  const resumeId = session?.resumeId;

  const { messages, connected, busy, error, send, interrupt } = useChatSocket({
    cwd,
    resumeId,
    enabled,
  });

  const scrollerRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    if (scrollerRef.current) {
      scrollerRef.current.scrollTop = scrollerRef.current.scrollHeight;
    }
  }, [messages]);

  if (!session) {
    return (
      <div className="flex-1 grid place-items-center text-center px-8">
        <div>
          <div className="text-muted text-sm mb-2">没有进行中的对话</div>
          <div className="text-dim text-xs">从左侧选择项目或点 + 新对话</div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col flex-1 min-h-0">
      <StatusRow connected={connected} busy={busy} error={error} onInterrupt={interrupt} />
      <div ref={scrollerRef} className="flex-1 overflow-y-auto px-6 py-5">
        {messages.length === 0 && (
          <div className="text-center text-dim text-xs mt-12">
            {connected ? '开始对话' : '正在连接服务端…'}
          </div>
        )}
        {messages.map((m) => (
          <RenderTurn key={m.id} turn={m} />
        ))}
      </div>
      {busy && <div className="h-[2px] w-full bg-accent/30 overflow-hidden relative">
        <div className="absolute inset-y-0 left-0 w-1/3 bg-accent animate-pulse" />
      </div>}
      <Composer enabled={connected && !busy} onSend={send} />
    </div>
  );
}

function RenderTurn({ turn }: { turn: ChatTurn }) {
  switch (turn.kind) {
    case 'local-user':
      return <LocalUserMessage text={(turn.payload as { text: string }).text} />;
    case 'assistant':
      return <AssistantMessage payload={turn.payload as any} />;
    case 'tool-result':
      return <UserToolResults payload={turn.payload as any} />;
    case 'system-result':
      return <ResultLine payload={turn.payload as any} />;
    case 'error':
      return <ErrorLine payload={turn.payload as any} />;
  }
}

function StatusRow({
  connected,
  busy,
  error,
  onInterrupt,
}: {
  connected: boolean;
  busy: boolean;
  error: string | null;
  onInterrupt: () => void;
}) {
  const dotColor = error
    ? 'bg-red-400'
    : connected
      ? busy
        ? 'bg-yellow-400'
        : 'bg-emerald-400'
      : 'bg-dim';
  const text = error ? 'error' : connected ? (busy ? 'streaming' : 'ready') : 'connecting…';
  return (
    <div className="flex items-center gap-3 px-6 py-2 bg-surface/60 border-b border-border text-[11px] text-muted">
      <span className={`w-1.5 h-1.5 rounded-full ${dotColor}`} />
      <span>{text}</span>
      <span className="text-dim">·</span>
      <span className="font-mono">sonnet-4.6</span>
      {busy && (
        <button
          onClick={onInterrupt}
          className="ml-auto flex items-center gap-1.5 text-red-400 hover:text-red-300"
        >
          <StopCircle size={12} />
          stop
        </button>
      )}
    </div>
  );
}

function Composer({ enabled, onSend }: { enabled: boolean; onSend: (text: string) => void }) {
  const [text, setText] = useState('');
  const submit = () => {
    onSend(text);
    setText('');
  };
  return (
    <div className="border-t border-border px-4 py-3 flex items-end gap-2 bg-bg">
      <button className="p-2 text-muted hover:text-text rounded" disabled={!enabled} title="附件">
        <Paperclip size={16} />
      </button>
      <button className="p-2 text-muted hover:text-text rounded font-mono text-sm" disabled={!enabled} title="@ 文件">
        <AtSign size={16} />
      </button>
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        disabled={!enabled}
        placeholder={enabled ? 'Ask Claude…' : 'Connecting…'}
        rows={1}
        onKeyDown={(e) => {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            submit();
          }
        }}
        className="flex-1 resize-none bg-surfaceHi border border-border rounded-md px-3 py-2 text-[14px] text-text placeholder:text-dim focus:outline-none focus:border-accent disabled:opacity-50 max-h-32"
      />
      <button
        onClick={submit}
        disabled={!enabled || !text.trim()}
        className="p-2.5 rounded-md bg-accent text-white disabled:bg-surfaceHi disabled:text-dim"
        title="发送 (Enter)"
      >
        <ArrowUp size={16} />
      </button>
    </div>
  );
}
