import { describe, expect, test } from "bun:test";
import { changelog } from "./changelog";

const semver = /^\d+\.\d+\.\d+$/;
const isoDate = /^\d{4}-\d{2}-\d{2}$/;
const releaseKeys = ["version", "date", "new", "fixed"];
const itemKeys = ["title", "text", "pr"];

function semverKey(version: string): number[] {
  return version.split(".").map(Number);
}

function isRealCalendarDate(date: string): boolean {
  const [y, m, d] = date.split("-").map(Number);
  const parsed = new Date(Date.UTC(y, m - 1, d));
  return (
    parsed.getUTCFullYear() === y &&
    parsed.getUTCMonth() === m - 1 &&
    parsed.getUTCDate() === d
  );
}

describe("changelog data", () => {
  test("has at least one release", () => {
    expect(changelog.releases.length).toBeGreaterThan(0);
  });

  test("every release is well formed", () => {
    for (const release of changelog.releases) {
      expect(release.version).toMatch(semver);
      expect(release.date).toMatch(isoDate);
      expect(isRealCalendarDate(release.date)).toBe(true);

      const items = [...(release.new ?? []), ...(release.fixed ?? [])];
      expect(items.length).toBeGreaterThan(0);
      for (const item of items) {
        expect(item.text.trim().length).toBeGreaterThan(0);
        if (item.title !== undefined) {
          expect(item.title.trim().length).toBeGreaterThan(0);
        }
        if (item.pr !== undefined) {
          expect(Number.isInteger(item.pr)).toBe(true);
          expect(item.pr).toBeGreaterThan(0);
        }
      }
    }
  });

  test("releases and items only use known keys", () => {
    for (const release of changelog.releases) {
      for (const key of Object.keys(release)) {
        expect(releaseKeys).toContain(key);
      }
      const items = [...(release.new ?? []), ...(release.fixed ?? [])];
      for (const item of items) {
        for (const key of Object.keys(item)) {
          expect(itemKeys).toContain(key);
        }
      }
    }
  });

  test("item texts are unique within each release", () => {
    for (const release of changelog.releases) {
      const texts = [...(release.new ?? []), ...(release.fixed ?? [])].map(
        (item) => item.text,
      );
      expect(new Set(texts).size).toBe(texts.length);
    }
  });

  test("versions are unique and newest first", () => {
    const versions = changelog.releases.map((release) => release.version);
    expect(new Set(versions).size).toBe(versions.length);

    const keys = versions.map(semverKey);
    const sorted = [...keys].sort((a, b) =>
      b[0] - a[0] || b[1] - a[1] || b[2] - a[2],
    );
    expect(keys).toEqual(sorted);
  });
});
