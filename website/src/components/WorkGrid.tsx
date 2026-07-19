import type { ComponentType, SVGProps } from "react";
import {
  CalendarIcon,
  FeatherIcon,
  KeyboardIcon,
  MenuBarIcon,
  PowerIcon,
  RefreshIcon,
  SortIcon,
  SwipeIcon,
} from "./Icons";

type Item = {
  icon: ComponentType<SVGProps<SVGSVGElement>>;
  title: string;
  body: string;
};

const items: Array<Item> = [
  {
    icon: CalendarIcon,
    title: "Menu-bar only, on purpose",
    body: "No dock icon, no windows vying for attention. One click on the menu bar and your day unfolds; click away and it’s gone.",
  },
  {
    icon: RefreshIcon,
    title: "Always quietly fresh",
    body: "Dayline refreshes your calendar, issues, and notes in the background on a cadence you choose.",
  },
  {
    icon: KeyboardIcon,
    title: "Keyboard first",
    body: "Hover an issue and press C to copy its URL, S for status, P for priority. Remap them to whatever your fingers prefer.",
  },
  {
    icon: SwipeIcon,
    title: "Swipe to act",
    body: "A horizontal swipe across an issue reveals Cancel; across a note, Delete. No confirmation dialogs, no fuss.",
  },
  {
    icon: PowerIcon,
    title: "Launch at login",
    body: "Flip one switch and Dayline is just there every morning, like it should be.",
  },
  {
    icon: SortIcon,
    title: "Sorted your way",
    body: "Order Linear issues by what matters to you, and notes by updated, created, or title. Your day, your order.",
  },
  {
    icon: FeatherIcon,
    title: "Light enough to forget",
    body: "Native SwiftUI keeps Dayline lightweight and fast, using next to no system resources while it waits in your menu bar.",
  },
  {
    icon: MenuBarIcon,
    title: "Your next event, always visible",
    body: "The next calendar event and its countdown appear directly in the menu bar, so you know what’s coming without opening a thing.",
  },
];

export function WorkGrid() {
  return (
    <section className="mx-auto w-full max-w-5xl px-6 py-20 sm:py-28">
      <h2 className="text-center font-display text-4xl tracking-tight text-balance sm:text-5xl">
        Built for how you actually work
      </h2>
      <div className="mt-14 grid overflow-hidden rounded-3xl border border-line bg-card sm:mt-20 sm:grid-cols-2">
        {items.map((item, index) => (
          <div
            key={item.title}
            className={`border-line p-8 sm:p-10 ${
              index % 2 === 0 ? "sm:border-r" : ""
            } ${index < items.length - 2 ? "sm:border-b" : ""} ${
              index < items.length - 1 ? "max-sm:border-b" : ""
            }`}
          >
            <item.icon className="h-6 w-6 text-ember" />
            <h3 className="mt-4 font-display text-2xl tracking-tight">
              {item.title}
            </h3>
            <p className="mt-2.5 text-sm leading-relaxed text-mute">
              {item.body}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}
