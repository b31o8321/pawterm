import { MoreVertical } from 'lucide-react';

import { useAppStore } from '../state/store';

export function Header() {
  const session = useAppStore((s) => s.currentSession);
  return (
    <header className="px-5 py-3 border-b border-border flex items-center gap-3">
      <div className="min-w-0">
        <div className="text-[14px] font-semibold text-text leading-tight truncate">
          {session?.label ?? 'No session'}
        </div>
        {session && (
          <div className="text-[10px] text-dim font-mono leading-tight truncate">{session.cwd}</div>
        )}
      </div>
      <button className="ml-auto p-2 rounded text-muted hover:text-text hover:bg-surfaceHi">
        <MoreVertical size={16} />
      </button>
    </header>
  );
}
