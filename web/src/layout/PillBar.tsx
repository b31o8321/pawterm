import { FileCode, GitBranch, MessageCircle, Terminal as TerminalIcon } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

import { useAppStore, type TabId } from '../state/store';

const tabs: Array<{ id: TabId; label: string; icon: LucideIcon }> = [
  { id: 'chat', label: 'Chat', icon: MessageCircle },
  { id: 'shell', label: 'Shell', icon: TerminalIcon },
  { id: 'files', label: 'Files', icon: FileCode },
  { id: 'git', label: 'Git', icon: GitBranch },
];

export function PillBar() {
  const active = useAppStore((s) => s.activeTab);
  const setTab = useAppStore((s) => s.setTab);

  return (
    <div className="px-4 py-2 border-b border-border flex gap-2 overflow-x-auto">
      {tabs.map((t) => {
        const Icon = t.icon;
        const selected = t.id === active;
        return (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={`h-8 px-3 rounded-full flex items-center gap-1.5 text-[13px] transition-colors shrink-0 ${
              selected
                ? 'bg-accent/15 border border-accent text-accent font-semibold'
                : 'bg-surface border border-border text-muted hover:text-text hover:border-text/30'
            }`}
          >
            <Icon size={14} />
            {t.label}
          </button>
        );
      })}
    </div>
  );
}
