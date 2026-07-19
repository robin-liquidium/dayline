import type { ReactNode } from "react";
import { Footer } from "./Footer";
import { Nav } from "./Nav";

type LegalPageProps = {
  title: string;
  summary: string;
  updated: string;
  children: ReactNode;
};

export function LegalPage({ title, summary, updated, children }: LegalPageProps) {
  return (
    <div className="min-h-screen">
      <Nav />
      <main className="mx-auto w-full max-w-3xl px-6 pb-24 pt-14 sm:pt-20">
        <header className="border-b border-line pb-10">
          <p className="eyebrow">Dayline legal</p>
          <h1 className="mt-4 font-display text-5xl tracking-tight sm:text-6xl">
            {title}
          </h1>
          <p className="mt-5 max-w-2xl text-lg leading-relaxed text-mute">
            {summary}
          </p>
          <p className="mt-5 text-sm text-mute">Last updated {updated}</p>
        </header>

        <div className="mt-12 space-y-12 text-[15px] leading-7 text-mute">
          {children}
        </div>
      </main>
      <Footer showSupport={false} />
    </div>
  );
}

export function LegalSection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section>
      <h2 className="font-display text-3xl tracking-tight text-ink">{title}</h2>
      <div className="mt-4 space-y-4">{children}</div>
    </section>
  );
}
