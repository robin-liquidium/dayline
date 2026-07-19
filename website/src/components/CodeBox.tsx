import { useState } from "react";
import { CheckIcon, CopyIcon } from "./Icons";

export function CodeBox({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      // clipboard unavailable (non-secure context); nothing to do
    }
  };

  return (
    <div className="inline-flex items-center gap-3 rounded-xl border border-line bg-sand px-4 py-2.5">
      <code className="font-mono text-sm text-ink">
        <span className="mr-2 select-none text-mute">$</span>
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        aria-label="Copy install command"
        className="text-mute transition-colors hover:text-ink"
      >
        {copied ? (
          <CheckIcon className="h-4 w-4 text-ember" />
        ) : (
          <CopyIcon className="h-4 w-4" />
        )}
      </button>
    </div>
  );
}
