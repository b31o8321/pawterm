import { FileCode, GitBranch } from 'lucide-react';

import { Header } from './layout/Header';
import { PillBar } from './layout/PillBar';
import { Sidebar } from './layout/Sidebar';
import { useAppStore } from './state/store';
import { ChatTab } from './tabs/ChatTab';
import { Placeholder } from './tabs/Placeholder';
import { ShellTab } from './tabs/ShellTab';

export function App() {
  const tab = useAppStore((s) => s.activeTab);

  return (
    <div className="flex h-full bg-bg text-text">
      <Sidebar />
      <main className="flex-1 flex flex-col min-w-0">
        <Header />
        <PillBar />
        {tab === 'chat' && <ChatTab />}
        {tab === 'shell' && <ShellTab />}
        {tab === 'files' && <Placeholder icon={FileCode} title="Files" subtitle="文件树（待实现）" />}
        {tab === 'git' && <Placeholder icon={GitBranch} title="Git" subtitle="diff / stage / commit（待实现）" />}
      </main>
    </div>
  );
}
