import { Link } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { site } from "../site";
import { CheckIcon, CopyIcon, GithubIcon } from "./Icons";

const wallets = [
  {
    name: "Bitcoin",
    address: "bc1qv477t9sduhvnffyh76t6yha2x9s47wl55ccrkm",
  },
  {
    name: "Ethereum",
    address: "0x6E88665F234920c0EcB8115F8c287D3C31cFAA51",
  },
  {
    name: "Solana",
    address: "93Q1aChBp7qh2E9QaHa8J3RXJ2GJUuLTdknAnVLNnZp",
  },
];

function CoffeeWallets() {
  const [copied, setCopied] = useState<string | null>(null);
  const resetTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);

  const copy = async (name: string, address: string) => {
    try {
      await navigator.clipboard.writeText(address);
      setCopied(name);
      if (resetTimeout.current) clearTimeout(resetTimeout.current);
      resetTimeout.current = setTimeout(() => setCopied(null), 1600);
    } catch {
      // Clipboard access can be unavailable outside a secure context.
    }
  };

  return (
    <div className="mt-10 grid gap-7 border-t border-line pt-8 sm:grid-cols-[minmax(0,0.65fr)_minmax(0,1.35fr)] sm:gap-12">
      <div>
        <h2 className="font-display text-2xl tracking-tight text-ink">
          Buy me a coffee
        </h2>
        <p className="mt-2 max-w-sm text-sm leading-relaxed text-mute">
          If Dayline makes your day a little easier, you can support its
          continued development.
        </p>
      </div>

      <div className="divide-y divide-line border-y border-line">
        {wallets.map((wallet) => {
          const isCopied = copied === wallet.name;

          return (
            <div
              key={wallet.name}
              className="grid grid-cols-[5.5rem_minmax(0,1fr)_2rem] items-center gap-3 py-3"
            >
              <span className="text-xs font-medium text-ink">
                {wallet.name}
              </span>
              <code
                className="min-w-0 overflow-hidden text-ellipsis whitespace-nowrap font-mono text-[11px] text-mute"
                title={wallet.address}
              >
                {wallet.address}
              </code>
              <button
                type="button"
                onClick={() => copy(wallet.name, wallet.address)}
                aria-label={`Copy ${wallet.name} address`}
                title={isCopied ? "Copied" : `Copy ${wallet.name} address`}
                className="flex h-8 w-8 items-center justify-center rounded-full text-mute transition-colors hover:bg-sand hover:text-ink"
              >
                {isCopied ? (
                  <CheckIcon className="h-4 w-4 text-ember" />
                ) : (
                  <CopyIcon className="h-4 w-4" />
                )}
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export function Footer({ showSupport = true }: { showSupport?: boolean }) {
  return (
    <footer className="border-t border-line">
      <div className="mx-auto w-full max-w-5xl px-6 py-10 text-sm text-mute">
        <div className="flex flex-col items-center justify-between gap-4 sm:flex-row">
          <div className="flex items-center gap-2.5">
            <img
              src="/images/icon-256.webp"
              alt=""
              className="h-6 w-6 rounded-[22%]"
            />
            <span className="font-display text-lg text-ink">Dayline</span>
            <span aria-hidden="true">·</span>
            <span>© {new Date().getFullYear()}</span>
          </div>
          <div className="flex items-center gap-6">
            <Link to="/privacy" className="transition-colors hover:text-ink">
              Privacy
            </Link>
            <Link to="/terms" className="transition-colors hover:text-ink">
              Terms
            </Link>
            <a
              href={site.githubUrl}
              target="_blank"
              rel="noreferrer"
              className="flex items-center gap-1.5 transition-colors hover:text-ink"
            >
              <GithubIcon className="h-4 w-4" />
              GitHub
            </a>
            <a
              href={site.releasesUrl}
              target="_blank"
              rel="noreferrer"
              className="transition-colors hover:text-ink"
            >
              Releases
            </a>
          </div>
        </div>

        {showSupport ? <CoffeeWallets /> : null}
      </div>
    </footer>
  );
}
