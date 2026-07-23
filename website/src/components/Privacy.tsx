import { site } from "../site";

type Row = {
  label: string;
  on: boolean;
};

const rows: Array<Row> = [
  { label: "OAuth tokens in the macOS Keychain", on: true },
  { label: "Secure provider sign-in, no client secrets", on: true },
  { label: "Direct Google, Linear & GitHub API connections", on: true },
  { label: "Notes stored locally on your Mac", on: true },
  { label: "Analytics and tracking", on: false },
  { label: "Third-party Dayline servers", on: false },
];

function Toggle({ on }: { on: boolean }) {
  return (
    <span
      aria-hidden="true"
      className={`relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors ${
        on ? "bg-ember" : "bg-line"
      }`}
    >
      <span
        className={`inline-block h-4.5 w-4.5 transform rounded-full bg-white shadow transition-transform ${
          on ? "translate-x-5.5" : "translate-x-1"
        }`}
      />
    </span>
  );
}

export function Privacy() {
  return (
    <section className="mx-auto w-full max-w-5xl px-6 py-20 sm:py-28">
      <div className="grid items-center gap-12 sm:grid-cols-2 sm:gap-16">
        <div>
          <h2 className="font-display text-4xl tracking-tight text-balance sm:text-5xl">
            Local first, with you in control
          </h2>
          <p className="mt-5 leading-relaxed text-mute">
            Dayline has no backend and no account system. Your Mac talks
            straight to Google, Linear, and GitHub over HTTPS, tokens live in the
            Keychain, and notes never leave your disk. Disconnect accounts from
            Settings at any time to remove their local credentials.
          </p>
          <a
            href={`${site.githubUrl}#readme`}
            target="_blank"
            rel="noreferrer"
            className="mt-5 inline-block text-sm font-medium text-ember underline-offset-4 hover:underline"
          >
            Read the details in the README →
          </a>
        </div>
        <div className="overflow-hidden rounded-3xl border border-line bg-card shadow-lg shadow-amber-900/5">
          {rows.map((row, index) => (
            <div
              key={row.label}
              className={`flex items-center justify-between gap-6 px-6 py-4 ${
                index < rows.length - 1 ? "border-b border-line" : ""
              }`}
            >
              <span className="text-sm">{row.label}</span>
              <span className="flex items-center gap-2.5">
                <span
                  className={`text-xs font-medium ${
                    row.on ? "text-ember" : "text-mute"
                  }`}
                >
                  {row.on ? "On" : "Off"}
                </span>
                <Toggle on={row.on} />
              </span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
