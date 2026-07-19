import type { SVGProps } from "react";

type IconProps = SVGProps<SVGSVGElement>;

function base(props: IconProps) {
  return {
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.8,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    viewBox: "0 0 24 24",
    ...props,
  };
}

export function CalendarIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <rect x="3" y="4.5" width="18" height="16" rx="3" />
      <path d="M8 2.5v4M16 2.5v4M3 9.5h18" />
    </svg>
  );
}

export function LinearIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M4 15.5 15.5 4" />
      <path d="M4 10.8 10.8 4" />
      <path d="M4 20.2 20.2 4" opacity="0.45" />
      <path d="M8.5 20h11.5" opacity="0.45" />
    </svg>
  );
}

export function NoteIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M5 3.5h11l3 3V20.5H5z" />
      <path d="M16 3.5v3h3" />
      <path d="M8.5 11h7M8.5 14.5h7M8.5 18h4" />
    </svg>
  );
}

export function RefreshIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M20 12a8 8 0 1 1-2.34-5.66" />
      <path d="M20 3.5V8h-4.5" />
    </svg>
  );
}

export function KeyboardIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <rect x="2.5" y="6" width="19" height="12" rx="2.5" />
      <path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M6 14h.01M18 14h.01M9 14h6" />
    </svg>
  );
}

export function SwipeIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M8 12H3m0 0 3-3M3 12l3 3" />
      <path d="M16 12h5m0 0-3-3m3 3-3 3" />
      <rect x="10.5" y="7" width="3" height="10" rx="1.5" />
    </svg>
  );
}

export function PowerIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M12 3v8" />
      <path d="M6.3 6.3a8 8 0 1 0 11.4 0" />
    </svg>
  );
}

export function SortIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M4 6h16M6 12h12M9 18h6" />
    </svg>
  );
}

export function FeatherIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M20.5 3.5c-7 0-12 3.5-14.5 9.5l-2.5 7.5" />
      <path d="M20.5 3.5c0 7-4 11-10.5 11.5" />
      <path d="m7 13 4 4M11 9l4 4" />
    </svg>
  );
}

export function MenuBarIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <rect x="2.5" y="5" width="19" height="14" rx="3" />
      <path d="M2.5 9h19" />
      <rect x="12" y="6.5" width="6.5" height="1" rx=".5" />
    </svg>
  );
}

export function KeyIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <circle cx="8" cy="15" r="4.5" />
      <path d="m11.5 11.5 8-8M17 5l2.5 2.5M14 8l2 2" />
    </svg>
  );
}

export function ShieldIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M12 3 5 5.5v5c0 4.7 3 8.4 7 10 4-1.6 7-5.3 7-10v-5z" />
      <path d="m9 12 2 2 4-4" />
    </svg>
  );
}

export function ServerOffIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M4 4 20 20" />
      <rect x="3" y="5" width="18" height="6" rx="2" />
      <rect x="3" y="13" width="18" height="6" rx="2" />
      <path d="M7 8h.01M7 16h.01" />
    </svg>
  );
}

export function DownloadIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M12 3.5v11m0 0 4-4m-4 4-4-4" />
      <path d="M4.5 17v2A1.5 1.5 0 0 0 6 20.5h12a1.5 1.5 0 0 0 1.5-1.5v-2" />
    </svg>
  );
}

export function GithubIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path d="M12 .5C5.65.5.5 5.65.5 12c0 5.08 3.29 9.39 7.86 10.91.58.11.79-.25.79-.55 0-.27-.01-1.17-.02-2.12-3.2.7-3.88-1.36-3.88-1.36-.52-1.33-1.28-1.68-1.28-1.68-1.04-.71.08-.7.08-.7 1.15.08 1.76 1.18 1.76 1.18 1.03 1.76 2.7 1.25 3.35.96.1-.75.4-1.25.72-1.54-2.55-.29-5.24-1.28-5.24-5.68 0-1.26.45-2.28 1.18-3.09-.12-.29-.51-1.46.11-3.05 0 0 .96-.31 3.15 1.18a10.9 10.9 0 0 1 5.74 0c2.19-1.49 3.15-1.18 3.15-1.18.62 1.59.23 2.76.11 3.05.74.81 1.18 1.83 1.18 3.09 0 4.42-2.7 5.39-5.26 5.67.41.35.78 1.05.78 2.12 0 1.53-.01 2.76-.01 3.14 0 .3.2.66.8.55A11.51 11.51 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5Z" />
    </svg>
  );
}

export function CopyIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <rect x="9" y="9" width="11" height="11" rx="2" />
      <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
    </svg>
  );
}

export function CheckIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="m4.5 12.5 5 5 10-11" />
    </svg>
  );
}
