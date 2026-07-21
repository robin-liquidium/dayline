import type { ReactNode } from "react";
import {
  HeadContent,
  Outlet,
  Scripts,
  createRootRoute,
} from "@tanstack/react-router";
import appCss from "../styles.css?url";
import { site } from "../site";

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { title: `Dayline — ${site.tagline}` },
      { name: "description", content: site.description },
      { property: "og:title", content: `Dayline — ${site.tagline}` },
      { property: "og:description", content: site.description },
      { property: "og:type", content: "website" },
      {
        property: "og:image",
        content: "https://dayline.robin.build/images/og.png?v=2",
      },
      { property: "og:image:width", content: "1200" },
      { property: "og:image:height", content: "630" },
      {
        property: "og:image:alt",
        content: `Dayline. ${site.tagline}`,
      },
      { name: "twitter:card", content: "summary_large_image" },
      { name: "twitter:title", content: `Dayline — ${site.tagline}` },
      { name: "twitter:description", content: site.description },
      {
        name: "twitter:image",
        content: "https://dayline.robin.build/images/og.png?v=2",
      },
      { name: "twitter:image:alt", content: `Dayline. ${site.tagline}` },
    ],
    links: [
      { rel: "stylesheet", href: appCss },
      { rel: "icon", type: "image/png", href: "/images/favicon.png?v=3" },
      { rel: "preconnect", href: "https://fonts.googleapis.com" },
      {
        rel: "preconnect",
        href: "https://fonts.gstatic.com",
        crossOrigin: "anonymous",
      },
      {
        rel: "stylesheet",
        href: "https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=JetBrains+Mono:wght@400;500&display=swap",
      },
    ],
  }),
  component: RootComponent,
});

function RootComponent() {
  return (
    <RootDocument>
      <Outlet />
    </RootDocument>
  );
}

function RootDocument({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="en">
      <head>
        <HeadContent />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  );
}
