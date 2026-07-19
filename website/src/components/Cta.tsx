import { site } from "../site";
import { CodeBox } from "./CodeBox";
import { DownloadIcon } from "./Icons";

export function Cta() {
  return (
    <section className="mx-auto w-full max-w-5xl px-6 py-24 text-center sm:py-32">
      <h2 className="font-display text-5xl tracking-tight text-balance sm:text-6xl">
        Ready for a better day?
      </h2>
      <p className="mx-auto mt-5 max-w-md leading-relaxed text-mute">
        One tiny app for the things you check twenty times a day. Free and open
        source.
      </p>
      <div className="mt-9 flex flex-col items-center gap-4">
        <a
          href={site.downloadUrl}
          className="flex items-center gap-2.5 rounded-full bg-ink px-7 py-3.5 text-base font-medium text-cream shadow-sm transition-all hover:bg-black hover:shadow-md"
        >
          <DownloadIcon className="h-5 w-5" />
          Download Dayline
        </a>
        <CodeBox command={site.brewCommand} />
        <p className="text-xs text-mute">{site.systemNote}</p>
      </div>
    </section>
  );
}
