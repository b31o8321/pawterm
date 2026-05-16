import type { LucideIcon } from 'lucide-react';

interface Props {
  icon: LucideIcon;
  title: string;
  subtitle?: string;
}

export function Placeholder({ icon: Icon, title, subtitle }: Props) {
  return (
    <div className="flex-1 grid place-items-center px-8 text-center">
      <div>
        <Icon size={32} className="mx-auto text-dim mb-3" />
        <div className="text-muted text-sm font-medium">{title}</div>
        {subtitle && <div className="text-dim text-xs mt-1">{subtitle}</div>}
      </div>
    </div>
  );
}
