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

        <ol className="mt-12 space-y-12">
          {changelog.releases.map((release, index) => (
            <ReleaseEntry
              key={release.version}
              release={release}
              isLatest={index === 0}
              isFirst={index === 0}
            />
          ))}
        </ol>
      </main>
      <Footer showSupport={false} />
    </div>
  );
}

function ReleaseEntry({
  release,
  isLatest,
  isFirst,
}: {
  release: ChangelogRelease;
  isLatest: boolean;
  isFirst: boolean;
}) {
  const items = [...(release.new ?? []), ...(release.fixed ?? [])];

  return (
    <li className={isFirst ? "" : "border-t border-line pt-12"}>
      <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1">
        <h2 className="font-display text-3xl tracking-tight text-ink">
          {release.version}
        </h2>
        {isLatest ? (
          <span className="font-display text-lg italic text-ember">Latest</span>
        ) : null}
        <time className="text-sm text-mute">
          {formatChangelogDate(release.date)}
        </time>
      </div>

      <div className="mt-4 space-y-3 text-[15px] leading-7 text-mute">
        {items.map((item) => (
          <ItemParagraph key={item.text} item={item} />
        ))}
      </div>
    </li>
  );
}

function ItemParagraph({ item }: { item: ChangelogItem }) {
  return (
    <p>
      {item.title ? (
        <span className="text-ink">{item.title} — </span>
      ) : null}
      {item.text}
    </p>
  );
}
