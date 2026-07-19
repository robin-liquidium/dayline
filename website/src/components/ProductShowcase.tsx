const showcases = [
  {
    title: "Change priority without breaking focus",
    body: "Hover an issue, tap P, and keep moving. The same quick picker handles status changes with S.",
    image: "/images/linear-priority-picker.avif",
    alt: "Dayline Linear priority picker",
    width: 1154,
    height: 1067,
    className: "sm:col-span-2",
    imageClassName: "mx-auto w-full max-w-md sm:mx-0",
  },
  {
    title: "Create the issue while it is fresh",
    body: "Capture the title, owner, due date, description, and the advanced details without opening a browser tab.",
    image: "/images/linear-issue-editor.avif",
    alt: "Dayline new Linear issue editor",
    width: 1203,
    height: 1170,
    className: "",
    imageClassName: "w-full",
  },
  {
    title: "Tune it once, then forget it",
    body: "Choose refresh timing, meeting-title behavior, shortcuts, sorting, and launch at login from one small settings window.",
    image: "/images/dayline-settings.avif",
    alt: "Dayline settings window",
    width: 1165,
    height: 1142,
    className: "",
    imageClassName: "w-full",
  },
];

function ShortcutOrb({
  shortcut,
  label,
  kind,
  className,
}: {
  shortcut: string;
  label: string;
  kind: "priority" | "status";
  className: string;
}) {
  return (
    <svg
      viewBox="0 0 240 240"
      aria-hidden="true"
      className={`text-line ${className}`}
    >
      <circle
        cx="120"
        cy="120"
        r="88"
        fill="none"
        stroke="currentColor"
        strokeWidth="1"
        opacity="0.6"
      />
      <circle
        cx="120"
        cy="120"
        r="62"
        fill="none"
        stroke="currentColor"
        strokeWidth="1"
        strokeDasharray="3 8"
        opacity="0.72"
      />

      <g>
        <rect
          x="86"
          y="86"
          width="68"
          height="68"
          rx="17"
          fill="var(--color-card)"
          stroke="currentColor"
          strokeWidth="1.2"
        />
        <rect
          x="94"
          y="94"
          width="52"
          height="52"
          rx="11"
          fill="none"
          stroke="currentColor"
          strokeWidth="1"
          opacity="0.65"
        />
        <text
          x="120"
          y="133"
          fill="var(--color-mute)"
          fontFamily="ui-sans-serif, system-ui, sans-serif"
          fontSize="30"
          fontWeight="500"
          textAnchor="middle"
        >
          {shortcut}
        </text>
        <text
          x="120"
          y="173"
          fill="var(--color-mute)"
          fontFamily="ui-sans-serif, system-ui, sans-serif"
          fontSize="11"
          textAnchor="middle"
          opacity="0.65"
        >
          {label}
        </text>
      </g>

      <g
        fill="var(--color-cream)"
        stroke="var(--color-ember)"
        strokeWidth="1.4"
        opacity="0.42"
      >
        {kind === "priority" ? (
          <rect x="170" y="49" width="22" height="22" rx="6" />
        ) : (
          <circle cx="181" cy="60" r="11" />
        )}
        <circle cx="194" cy="159" r="11" />
        <circle cx="52" cy="174" r="11" />
      </g>
      <g
        fill="none"
        stroke="var(--color-ember)"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.7"
        opacity="0.5"
      >
        {kind === "priority" ? (
          <>
            <path d="M181 55v6M181 65v.5" />
            <path d="m194 164 4-4m-4 4-4-4M194 164v-10" />
            <path d="m52 169 4 4m-4-4-4 4M52 169v10" />
          </>
        ) : (
          <>
            <circle cx="181" cy="60" r="3.5" />
            <path d="m188 159 4 4 7-8" />
            <path d="m48 170 8 8m0-8-8 8" />
          </>
        )}
      </g>
    </svg>
  );
}

function ShortcutGraphic() {
  return (
    <div className="relative mx-auto aspect-[1.05] w-full max-w-80 -translate-x-6">
      <ShortcutOrb
        shortcut="P"
        label="Priority"
        kind="priority"
        className="absolute -top-4 -left-12 w-[68%]"
      />
      <ShortcutOrb
        shortcut="S"
        label="Status"
        kind="status"
        className="absolute right-0 -bottom-4 w-[68%]"
      />
    </div>
  );
}

export function ProductShowcase() {
  return (
    <section className="mx-auto w-full max-w-5xl px-6 py-20 sm:py-28">
      <div className="mx-auto max-w-2xl text-center">
        <h2 className="font-display text-4xl tracking-tight text-balance sm:text-5xl">
          Small app. Surprisingly capable.
        </h2>
        <p className="mt-4 leading-relaxed text-mute text-balance">
          Dayline keeps the common actions close without turning your menu bar
          into another dashboard to manage.
        </p>
      </div>

      <div className="mt-20 grid gap-6 sm:mt-28 sm:grid-cols-2">
        {showcases.map((showcase, index) => (
          <article key={showcase.title} className={showcase.className}>
            {index === 0 ? (
              <div className="grid items-center gap-10 sm:grid-cols-[minmax(0,1fr)_minmax(15rem,0.6fr)] sm:gap-14">
                <img
                  src={showcase.image}
                  alt={showcase.alt}
                  width={showcase.width}
                  height={showcase.height}
                  loading="lazy"
                  className={showcase.imageClassName}
                />
                <div className="hidden sm:block">
                  <ShortcutGraphic />
                </div>
              </div>
            ) : (
              <img
                src={showcase.image}
                alt={showcase.alt}
                width={showcase.width}
                height={showcase.height}
                loading="lazy"
                className={showcase.imageClassName}
              />
            )}
            <h3 className="mt-5 font-display text-2xl tracking-tight">
              {showcase.title}
            </h3>
            <p className="mt-2 max-w-xl text-sm leading-relaxed text-mute">
              {showcase.body}
            </p>
          </article>
        ))}
      </div>
    </section>
  );
}
