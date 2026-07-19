import { site } from "../site";
import { DownloadIcon, GithubIcon } from "./Icons";

export function Nav() {
  return (
    <header className="mx-auto flex w-full max-w-5xl items-center justify-between px-6 py-6">
      <a href="/" className="flex items-center gap-2.5">
        <img
          src="/images/icon-256.webp"
          alt="Dayline app icon"
          className="h-8 w-8 rounded-[22%]"
        />
        <span className="font-display text-2xl tracking-tight">Dayline</span>
      </a>
      <nav className="flex items-center gap-2">
        <a
          href={site.githubUrl}
          target="_blank"
          rel="noreferrer"
          className="flex items-center gap-2 rounded-full px-4 py-2 text-sm text-mute transition-colors hover:text-ink"
        >
          <GithubIcon className="h-4 w-4" />
          <span className="hidden sm:inline">GitHub</span>
        </a>
        <a
          href={site.downloadUrl}
          className="flex items-center gap-2 rounded-full bg-ink px-4 py-2 text-sm font-medium text-cream transition-colors hover:bg-black"
        >
          <DownloadIcon className="h-4 w-4" />
          Download
        </a>
      </nav>
    </header>
  );
}
