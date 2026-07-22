import { createFileRoute } from "@tanstack/react-router";
import type { ChangelogItem, ChangelogRelease } from "../changelog";
import { changelog, formatChangelogDate } from "../changelog";
import { Footer } from "../components/Footer";
import { Nav } from "../components/Nav";

export const Route = createFileRoute("/changelog")({
  head: () => ({
    meta: [
      { title: "Changelog — Dayline" },
      {
        name: "description",
        content: "Every new feature, improvement, and fix in Dayline.",
      },
    ],
  }),
  component: ChangelogPage,
});

function ChangelogPage() {
  return (
    <div className="min-h-screen">
      <Nav />
      <main className="mx-auto w-full max-w-3xl px-6 pb-24 pt-14 sm:pt-20">
        <header className="border-b border-line pb-10">
          <p className="eyebrow">Dayline changelog</p>
          <h1 className="mt-4 font-display text-5xl tracking-tight sm:text-6xl">
            What&apos;s new
          </h1>
          <p className="mt-5 max-w-2xl text-lg leading-relaxed text-mute">
            Every feature, improvement, and fix — Dayline keeps getting a
            little better, one quiet release at a time.
          </p>
        </header>

        <ol className="mt-12 space-y-8">
          {changelog.releases.map((release, index) => (
            <ReleaseCard
              key={release.version}
              release={release}
              isLatest={index === 0}
            />
          ))}
        </ol>
      </main>
      <Footer showSupport={false} />
    </div>
  );
}

function ReleaseCard({
  release,
  isLatest,
}: {
  release: ChangelogRelease;
  isLatest: boolean;
}) {
  return (
    <li className="rounded-3xl border border-line bg-card p-7 shadow-sm shadow-amber-900/5 sm:p-8">
      <div className="flex flex-wrap items-center gap-3">
        <span className="rounded-full bg-ink px-3 py-1 font-mono text-xs font-medium text-cream">
          v{release.version}
        </span>
        {isLatest ? (
          <span className="rounded-full border border-glow/40 bg-glow/10 px-3 py-1 text-xs font-medium text-ember">
            Latest
          </span>
        ) : null}
        <time className="text-sm text-mute">
          {formatChangelogDate(release.date)}
        </time>
      </div>

      <div className="mt-6 space-y-6">
        {release.new?.length ? (
          <ReleaseSection title="New features" items={release.new} accent />
        ) : null}
        {release.fixed?.length ? (
          <ReleaseSection title="Improvements & bug fixes" items={release.fixed} />
        ) : null}
      </div>
    </li>
  );
}

function ReleaseSection({
  title,
  items,
  accent = false,
}: {
  title: string;
  items: ChangelogItem[];
  accent?: boolean;
}) {
  return (
    <section>
      <h2
        className={`text-xs font-semibold uppercase tracking-[0.14em] ${
          accent ? "text-ember" : "text-mute"
        }`}
      >
        {title}
      </h2>
      <ul className="mt-3 space-y-2.5">
        {items.map((item) => (
          <li
            key={item.text}
            className="flex gap-3 text-[15px] leading-7 text-ink"
          >
            <span
              aria-hidden="true"
              className={`mt-3 h-1.5 w-1.5 shrink-0 rounded-full ${
                accent ? "bg-glow" : "bg-line"
              }`}
            />
            {item.text}
          </li>
        ))}
      </ul>
    </section>
  );
}
