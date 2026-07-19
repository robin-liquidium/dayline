import { site } from "../site";
import { CodeBox } from "./CodeBox";
import { DownloadIcon } from "./Icons";

export function Hero() {
  return (
    <section className="mx-auto flex w-full max-w-5xl flex-col items-center px-6 pt-16 pb-10 text-center sm:pt-24">
      <img
        src="/images/icon-256.webp"
        alt="Dayline app icon"
        className="h-24 w-24 rounded-[22%] shadow-lg shadow-amber-900/10 ring-1 ring-line"
      />
      <h1 className="mt-8 max-w-2xl font-display text-5xl leading-[1.05] tracking-tight text-balance sm:text-7xl">
        Your whole day, one glance away.
      </h1>
      <p className="mt-6 max-w-xl text-lg leading-relaxed text-mute text-balance">
        Dayline lives in your menu bar and keeps your calendar, Linear issues,
        and notes in one quiet little place — so you always know what's next.
      </p>
      <div className="mt-9 flex flex-col items-center gap-4">
        <a
          href={site.downloadUrl}
          className="flex items-center gap-2.5 rounded-full bg-ink px-7 py-3.5 text-base font-medium text-cream shadow-sm transition-all hover:bg-black hover:shadow-md"
        >
          <DownloadIcon className="h-5 w-5" />
          Download for macOS
        </a>
        <CodeBox command={site.brewCommand} />
        <p className="text-xs text-mute">
          {site.systemNote} · Homebrew cask coming soon
        </p>
      </div>

      <div className="mt-16 w-full max-w-3xl">
        <img
          src="/images/dayline-menu-overview.avif"
          alt="The Dayline menu showing today's calendar events, Linear issues, and notes"
          width="1030"
          height="1614"
          className="mx-auto w-full max-w-md"
        />
        <p className="relative z-10 mx-auto -mt-6 w-fit text-sm text-mute">
          The whole app. Right in your menu bar.
        </p>
      </div>

      <div className="mt-24 text-center">
        <p className="font-display text-3xl tracking-tight sm:text-4xl">
          Connected to
        </p>
        <div className="mt-5 flex items-center justify-center gap-8 sm:gap-10">
          <img
            src="/images/linear-wordmark.svg"
            alt="Linear"
            className="h-6 w-auto"
          />
          <img
            src="/images/google-calendar-wordmark.webp"
            alt="Google Calendar"
            width="3113"
            height="403"
            className="h-6 w-auto"
          />
        </div>
      </div>
    </section>
  );
}
