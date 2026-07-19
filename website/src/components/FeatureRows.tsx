type Feature = {
  number: string;
  title: string;
  body: string;
  image: string;
  alt: string;
  width: number;
  height: number;
};

const features: Array<Feature> = [
  {
    number: "01",
    title: "Start your day knowing what’s next",
    body: "Up Next shows your remaining timed events for today, straight from Google Calendar. Tomorrow’s plan is one click away when you want a head start.",
    image: "/images/calendar-agenda.avif",
    alt: "Dayline showing upcoming events for today and tomorrow",
    width: 1071,
    height: 589,
  },
  {
    number: "02",
    title: "Your Linear issues, minus the tab",
    body: "Active issues assigned to you, sorted the way you like. Hover for hotkeys — copy the URL, change status, bump priority — or swipe a row to cancel it. New issue? One click.",
    image: "/images/linear-status-picker.avif",
    alt: "Dayline showing active Linear issues with the status picker open",
    width: 1552,
    height: 697,
  },
  {
    number: "03",
    title: "Notes that never leave your Mac",
    body: "Quick local notes, right next to your day. The first line becomes the title, more notes stay one click away, and everything is stored only on this Mac.",
    image: "/images/local-notes-list.avif",
    alt: "Dayline showing a list of local notes",
    width: 1093,
    height: 639,
  },
];

export function FeatureRows() {
  return (
    <section className="mx-auto w-full max-w-5xl px-6 py-20 sm:py-28">
      <h2 className="text-center font-display text-4xl tracking-tight text-balance sm:text-5xl">
        Dayline reads between the lines
      </h2>
      <div className="mt-16 flex flex-col gap-20 sm:mt-24 sm:gap-28">
        {features.map((feature, index) => (
          <div
            key={feature.number}
            className="grid items-center gap-8 sm:grid-cols-2 sm:gap-14"
          >
            <div className={index % 2 === 1 ? "sm:order-2" : ""}>
              <span className="eyebrow">{feature.number}</span>
              <h3 className="mt-3 font-display text-3xl tracking-tight text-balance sm:text-4xl">
                {feature.title}
              </h3>
              <p className="mt-4 max-w-md leading-relaxed text-mute">
                {feature.body}
              </p>
            </div>
            <div className={index % 2 === 1 ? "sm:order-1" : ""}>
              <picture>
                <source srcSet={feature.image} type="image/avif" />
                <source
                  srcSet={feature.image.replace(/\.avif$/, ".webp")}
                  type="image/webp"
                />
                <img
                  src={feature.image.replace(/\.avif$/, ".webp")}
                  alt={feature.alt}
                  width={feature.width}
                  height={feature.height}
                  loading="lazy"
                  className="mx-auto w-full"
                />
              </picture>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
