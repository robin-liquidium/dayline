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
    title: "Menu-bar first, on purpose",
    body: "Your day lives behind one menu bar click. Editors and searchable settings open as focused native windows, then Dayline slips out of the Dock when you close them.",
  },
  {
    icon: RefreshIcon,
    title: "Always quietly fresh",
    body: "Dayline refreshes calendars and issues in the background on a cadence you choose, and can install new versions automatically.",
  },
  {
    icon: KeyboardIcon,
    title: "Keyboard first",
    body: "Create notes or Linear and GitHub issues from anywhere. Hover an issue for configurable shortcuts to copy, change status, labels, assignees, and more.",
  },
  {
    icon: SwipeIcon,
    title: "Swipe to act",
    body: "Swipe a Linear issue to cancel it or a note to delete it. Dayline asks before it commits the destructive action.",
  },
  {
    icon: PowerIcon,
    title: "Launch at login",
    body: "Flip one switch and Dayline is just there every morning, like it should be.",
  },
  {
    icon: SortIcon,
    title: "Your menu, your rules",
    body: "Hide calendar, issues, or notes entirely. Pick your Linear teams and GitHub repositories, filter assigned or all-open work, and sort the rest your way.",
  },
  {
    icon: FeatherIcon,
    title: "Light enough to forget",
    body: "Native SwiftUI keeps Dayline lightweight and fast, using next to no system resources while it waits in your menu bar.",
  },
  {
    icon: MenuBarIcon,
    title: "Never miss the meeting",
    body: "The current or next event stays visible beside the clock. Optional full-screen alerts count down, open the meeting in one click, and dismiss with Esc.",
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
