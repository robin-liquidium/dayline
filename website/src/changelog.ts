import data from "../../changelog.json";

export type ChangelogItem = {
  title?: string;
  text: string;
  pr?: number;
};

export type ChangelogRelease = {
  version: string;
  date: string;
  new?: ChangelogItem[];
  fixed?: ChangelogItem[];
};

export type Changelog = {
  releases: ChangelogRelease[];
};

export const changelog: Changelog = data;

export function formatChangelogDate(iso: string): string {
  return new Date(`${iso}T00:00:00Z`).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  });
}
