interface Props {
  oldString: string;
  newString: string;
}

export function DiffView({ oldString, newString }: Props) {
  const oldLines = oldString ? oldString.split('\n') : [];
  const newLines = newString ? newString.split('\n') : [];

  return (
    <div className="rounded border border-border bg-bg overflow-hidden font-mono text-[11px]">
      {oldLines.map((line, i) => (
        <div key={`o${i}`} className="bg-red-500/10 text-red-300 px-2 py-0.5">
          <span className="select-none text-red-400/60">− </span>
          {line || ' '}
        </div>
      ))}
      {newLines.map((line, i) => (
        <div key={`n${i}`} className="bg-emerald-500/10 text-emerald-300 px-2 py-0.5">
          <span className="select-none text-emerald-400/60">+ </span>
          {line || ' '}
        </div>
      ))}
    </div>
  );
}
