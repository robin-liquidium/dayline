import { describe, expect, test } from "bun:test";
import {
  AmbiguousIssueCreationError,
  type FeedbackAttachmentStoreNamespace,
  type FeedbackEnvironment,
  handleFeedbackAttachmentRequest,
  handleFeedbackRequest,
  makeGitHubIssueDraft,
  resolveGitHubIssueCreation,
} from "./feedback";

function environment(
  options: {
    burstAllowed?: boolean;
    hourlyAllowed?: boolean;
    hourlyLimitFails?: boolean;
  } = {},
) {
  const burstKeys: string[] = [];
  const hourlyReservations: Array<{ hour: number; key: string; limit: number }> = [];
  const hourlyReleases: Array<{ hour: number; key: string }> = [];
  const mock: FeedbackEnvironment = {
    FEEDBACK_RATE_LIMIT: {
      limit: async ({ key }) => {
        burstKeys.push(key);
        return { success: options.burstAllowed ?? true };
      },
    },
    FEEDBACK_RATE_LIMITER: {
      getByName: (key) => ({
        reserve: async (hour, limit) => {
          hourlyReservations.push({ hour, key, limit });
          if (options.hourlyLimitFails) {
            throw new Error("simulated Durable Object failure");
          }
          return options.hourlyAllowed ?? true;
        },
        release: async (hour) => {
          hourlyReleases.push({ hour, key });
        },
      }),
    },
    FEEDBACK_RATE_LIMIT_SECRET: "x",
    GITHUB_APP_ID: "1",
    GITHUB_INSTALLATION_ID: "2",
    GITHUB_PRIVATE_KEY: "",
  };
  return { burstKeys, hourlyReleases, hourlyReservations, mock };
}

function feedbackRequest(
  body: unknown,
  url = "https://dayline.robin.build/api/feedback",
) {
  return new Request(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Dayline-Client": "macOS",
      "CF-Connecting-IP": "192.0.2.1",
    },
    body: JSON.stringify(body),
  });
}

interface TestZipEntry {
  path: string;
  data?: Uint8Array;
  compressedData?: Uint8Array;
  flags?: number;
  method?: number;
  uncompressedSize?: number;
  checksum?: number;
  madeBy?: number;
  externalAttributes?: number;
  localExtra?: Uint8Array;
  centralExtra?: Uint8Array;
  dataDescriptor?: "signed" | "unsigned";
}

interface TestZipOptions {
  prefix?: Uint8Array;
  gapBeforeCentral?: Uint8Array;
  unreferencedEntries?: readonly TestZipEntry[];
}

function diagnosticsZip(
  entries: readonly TestZipEntry[] = [
    {
      path: "Dayline Diagnostics/README.txt",
      data: new TextEncoder().encode("Dayline diagnostics"),
    },
  ],
  options: TestZipOptions = {},
): Uint8Array<ArrayBuffer> {
  const bytes: number[] = [...(options.prefix ?? new Uint8Array())];
  const centralRecords: number[][] = [];
  const write16 = (target: number[], value: number) => {
    target.push(value & 0xff, (value >>> 8) & 0xff);
  };
  const write32 = (target: number[], value: number) => {
    target.push(
      value & 0xff,
      (value >>> 8) & 0xff,
      (value >>> 16) & 0xff,
      (value >>> 24) & 0xff,
    );
  };
  const signature = (target: number[], value: number) => write32(target, value);

  const appendLocalEntry = (entry: TestZipEntry, includeInCentral: boolean) => {
    const name = [...new TextEncoder().encode(entry.path)];
    const uncompressedData = entry.data ?? new Uint8Array();
    const compressedData = entry.compressedData ?? uncompressedData;
    const checksum = entry.checksum ?? crc32(uncompressedData);
    const flags =
      (entry.flags ?? 0) | (entry.dataDescriptor === undefined ? 0 : 0x0008);
    const method = entry.method ?? 0;
    const uncompressedSize =
      entry.uncompressedSize ?? uncompressedData.byteLength;
    const localExtra = [...(entry.localExtra ?? new Uint8Array())];
    const centralExtra = [...(entry.centralExtra ?? new Uint8Array())];
    const localOffset = bytes.length;
    signature(bytes, 0x04034b50);
    write16(bytes, 20);
    write16(bytes, flags);
    write16(bytes, method);
    write16(bytes, 0);
    write16(bytes, 0);
    write32(bytes, entry.dataDescriptor ? 0 : checksum);
    write32(bytes, entry.dataDescriptor ? 0 : compressedData.byteLength);
    write32(bytes, entry.dataDescriptor ? 0 : uncompressedSize);
    write16(bytes, name.length);
    write16(bytes, localExtra.length);
    bytes.push(...name, ...localExtra, ...compressedData);
    if (entry.dataDescriptor) {
      if (entry.dataDescriptor === "signed") {
        signature(bytes, 0x08074b50);
      }
      write32(bytes, checksum);
      write32(bytes, compressedData.byteLength);
      write32(bytes, uncompressedSize);
    }

    if (!includeInCentral) {
      return;
    }
    const central: number[] = [];
    signature(central, 0x02014b50);
    write16(central, entry.madeBy ?? 20);
    write16(central, 20);
    write16(central, flags);
    write16(central, method);
    write16(central, 0);
    write16(central, 0);
    write32(central, checksum);
    write32(central, compressedData.byteLength);
    write32(central, uncompressedSize);
    write16(central, name.length);
    write16(central, centralExtra.length);
    write16(central, 0);
    write16(central, 0);
    write16(central, 0);
    write32(central, entry.externalAttributes ?? 0);
    write32(central, localOffset);
    central.push(...name, ...centralExtra);
    centralRecords.push(central);
  };

  for (const entry of entries) {
    appendLocalEntry(entry, true);
  }
  for (const entry of options.unreferencedEntries ?? []) {
    appendLocalEntry(entry, false);
  }

  bytes.push(...(options.gapBeforeCentral ?? new Uint8Array()));
  const centralOffset = bytes.length;
  for (const record of centralRecords) {
    bytes.push(...record);
  }
  const centralSize = bytes.length - centralOffset;
  signature(bytes, 0x06054b50);
  write16(bytes, 0);
  write16(bytes, 0);
  write16(bytes, entries.length);
  write16(bytes, entries.length);
  write32(bytes, centralSize);
  write32(bytes, centralOffset);
  write16(bytes, 0);
  return new Uint8Array(bytes);
}

function extraField(fieldID: number, data: Uint8Array): Uint8Array {
  const bytes = new Uint8Array(4 + data.byteLength);
  const view = new DataView(bytes.buffer);
  view.setUint16(0, fieldID, true);
  view.setUint16(2, data.byteLength, true);
  bytes.set(data, 4);
  return bytes;
}

function crc32(bytes: Iterable<number>): number {
  let checksum = 0xffffffff;
  for (const byte of bytes) {
    checksum ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      checksum =
        (checksum >>> 1) ^ (checksum & 1 ? 0xedb88320 : 0);
    }
  }
  return (checksum ^ 0xffffffff) >>> 0;
}

function encodedDiagnosticsZip(entries?: readonly TestZipEntry[]): string {
  return Buffer.from(diagnosticsZip(entries)).toString("base64");
}

async function deflateRaw(data: Uint8Array): Promise<Uint8Array<ArrayBuffer>> {
  const stream = new Blob([Uint8Array.from(data).buffer])
    .stream()
    .pipeThrough(new CompressionStream("deflate-raw"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

const macOS27DittoDiagnosticsFixture =
  "UEsDBAoAAAAAAM17+1wAAAAAAAAAAAAAAAAUABAARGF5bGluZSBEaWFnbm9zdGljcy9VWAwAcV1nanFdZ2r1AQAAUEsDBBQACAAIAM17+1wAAAAAAAAAAAAAAAAeABAARGF5bGluZSBEaWFnbm9zdGljcy9SRUFETUUudHh0VVgMAHFdZ2pxXWdq9QEAAHNJrMzJzEtVSMlMTM/LLy7JTC5WSMusKCktSuUCAFBLBwjn7tJ0HgAAABwAAABQSwECFQMKAAAAAADNe/tcAAAAAAAAAAAAAAAAFAAMAAAAAAAAAABA7UEAAAAARGF5bGluZSBEaWFnbm9zdGljcy9VWAgAcV1nanFdZ2pQSwECFQMUAAgACADNe/tc5+7SdB4AAAAcAAAAHgAMAAAAAAAAAABApIFCAAAARGF5bGluZSBEaWFnbm9zdGljcy9SRUFETUUudHh0VVgIAHFdZ2pxXWdqUEsFBgAAAAACAAIApgAAALwAAAAAAA==";

function attachmentStorage() {
  const archives = new Map<string, ArrayBuffer>();
  const namespace: FeedbackAttachmentStoreNamespace = {
    getByName: () => ({
      save: async (id, archive) => {
        archives.set(id, archive);
      },
      read: async (id) => archives.get(id) ?? null,
      remove: async (id) => {
        archives.delete(id);
      },
    }),
  };
  return { archives, namespace };
}

describe("feedback endpoint", () => {
  test("creates an anonymized public issue", async () => {
    const { burstKeys, hourlyReservations, mock } = environment();
    let capturedDraft: ReturnType<typeof makeGitHubIssueDraft> | undefined;
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message:
          "The menu disappears. \\@someone\rrobin-liquidium/dayline#123\nhttps://github.com/robin-liquidium/dayline/issues/123",
        metadata: {
          appVersion: "0.1.8",
          build: "33",
          macOSVersion: "26.0.0",
          architecture: "Apple Silicon",
        },
      }),
      mock,
      async (submission) => {
        capturedDraft = makeGitHubIssueDraft(submission);
        return { html_url: "https://github.com/example/issues/42", number: 42 };
      },
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      issueURL: "https://github.com/example/issues/42",
      issueNumber: 42,
    });
    expect(capturedDraft?.labels).toEqual(["feedback", "bug"]);
    expect(capturedDraft?.body).toContain("Dayline: 0.1.8 (build 33)");
    expect(capturedDraft?.body).toContain("    The menu disappears. \\@\u200Bsomeone");
    expect(capturedDraft?.body).not.toContain("\\@someone");
    expect(capturedDraft?.body).toContain("\n    robin-liquidium/dayline#123");
    expect(capturedDraft?.body).not.toContain("\nrobin-liquidium/dayline#123");
    expect(capturedDraft?.body).toContain("\n    https://github.com/robin-liquidium/dayline/issues/123");
    expect(capturedDraft?.body).not.toContain("192.0.2.1");
    expect(burstKeys[0]).not.toContain("192.0.2.1");
    expect(hourlyReservations).toHaveLength(1);
    expect(hourlyReservations[0]?.key).toBe(burstKeys[0]);
    expect(hourlyReservations[0]?.limit).toBe(3);
  });

  test("omits system information when the user opts out", async () => {
    const draft = makeGitHubIssueDraft({
      category: "feature",
      message: "Please add a weekly calendar view.",
    });

    expect(draft.labels).toEqual(["feedback", "enhancement"]);
    expect(draft.body).not.toContain("Anonymous system information");
  });

  test("stores explicitly included diagnostics and links them from the public issue", async () => {
    const { mock } = environment();
    const attachments = attachmentStorage();
    const archive = diagnosticsZip();
    let diagnosticsURL: string | undefined;
    let capturedDraft: ReturnType<typeof makeGitHubIssueDraft> | undefined;
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: Buffer.from(archive).toString("base64"),
      }),
      mock,
      async (submission) => {
        diagnosticsURL = submission.diagnosticsURL;
        capturedDraft = makeGitHubIssueDraft(submission);
        return { html_url: "https://github.com/example/issues/42", number: 42 };
      },
      mock.FEEDBACK_RATE_LIMITER,
      attachments.namespace,
    );

    expect(response.status).toBe(200);
    expect(diagnosticsURL).toMatch(
      /^https:\/\/dayline\.robin\.build\/api\/feedback\/diagnostics\/[0-9a-f-]{36}$/,
    );
    expect(capturedDraft?.body).toContain("## Diagnostics");
    expect(capturedDraft?.body).toContain("expires after 30 days");
    expect(capturedDraft?.body).not.toContain("No account, calendar");
    expect(attachments.archives.size).toBe(1);

    const download = await handleFeedbackAttachmentRequest(
      new Request(diagnosticsURL!),
      diagnosticsURL!.split("/").at(-1)!,
      attachments.namespace,
      mock,
    );
    expect(download.status).toBe(200);
    expect(download.headers.get("Content-Type")).toBe("application/zip");
    expect(download.headers.get("Content-Length")).toBe(
      archive.byteLength.toString(),
    );
    expect(download.headers.get("Content-Disposition")).toContain(
      "Dayline-Diagnostics.zip",
    );
    expect(new Uint8Array(await download.arrayBuffer())).toEqual(
      archive,
    );
  });

  test("accepts a real macOS 27 ditto archive with Unix extras and signed descriptors", async () => {
    const { mock } = environment();
    const attachments = attachmentStorage();
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: macOS27DittoDiagnosticsFixture,
      }),
      mock,
      async () => ({
        html_url: "https://github.com/example/issues/42",
        number: 42,
      }),
      mock.FEEDBACK_RATE_LIMITER,
      attachments.namespace,
    );

    expect(response.status).toBe(200);
    expect(attachments.archives.size).toBe(1);
  });

  test("rejects unsupported and missing diagnostic download routes", async () => {
    const { mock } = environment();
    const attachments = attachmentStorage();
    const attachmentID = crypto.randomUUID();

    const unsupportedMethod = await handleFeedbackAttachmentRequest(
      new Request(
        `https://dayline.robin.build/api/feedback/diagnostics/${attachmentID}`,
        { method: "POST" },
      ),
      attachmentID,
      attachments.namespace,
      mock,
    );
    expect(unsupportedMethod.status).toBe(405);
    expect(unsupportedMethod.headers.get("Allow")).toBe("GET");

    const invalidID = await handleFeedbackAttachmentRequest(
      new Request("https://dayline.robin.build/api/feedback/diagnostics/not-an-id"),
      "not-an-id",
      attachments.namespace,
      mock,
    );
    expect(invalidID.status).toBe(404);

    const missingStore = await handleFeedbackAttachmentRequest(
      new Request(
        `https://dayline.robin.build/api/feedback/diagnostics/${attachmentID}`,
      ),
      attachmentID,
      undefined,
      mock,
    );
    expect(missingStore.status).toBe(404);
  });

  test("rate limits public diagnostic downloads with a separate anonymous key", async () => {
    const { burstKeys, mock } = environment({ burstAllowed: false });
    const attachments = attachmentStorage();
    const attachmentID = crypto.randomUUID();
    const archive = diagnosticsZip();
    attachments.archives.set(attachmentID, Uint8Array.from(archive).buffer);

    const response = await handleFeedbackAttachmentRequest(
      new Request(
        `https://dayline.robin.build/api/feedback/diagnostics/${attachmentID}`,
        { headers: { "CF-Connecting-IP": "192.0.2.1" } },
      ),
      attachmentID,
      attachments.namespace,
      mock,
    );

    expect(response.status).toBe(429);
    expect(response.headers.get("Retry-After")).toBe("60");
    expect(await response.json()).toEqual({
      error: "Too many diagnostic downloads. Please try again in a minute.",
    });
    expect(burstKeys).toHaveLength(1);
    expect(burstKeys[0]?.startsWith("diagnostics:")).toBe(true);
    expect(burstKeys[0]).not.toContain("192.0.2.1");
  });

  test("uses the canonical website origin for diagnostic links", async () => {
    const { mock } = environment();
    const attachments = attachmentStorage();
    let diagnosticsURL: string | undefined;
    const response = await handleFeedbackRequest(
      feedbackRequest(
        {
          category: "bug",
          message: "The menu crashed while navigating with the keyboard.",
          diagnosticsArchive: encodedDiagnosticsZip(),
        },
        "https://preview.example/api/feedback",
      ),
      mock,
      async (submission) => {
        diagnosticsURL = submission.diagnosticsURL;
        return { html_url: "https://github.com/example/issues/42", number: 42 };
      },
      mock.FEEDBACK_RATE_LIMITER,
      attachments.namespace,
    );

    expect(response.status).toBe(200);
    expect(diagnosticsURL).toMatch(
      /^https:\/\/dayline\.robin\.build\/api\/feedback\/diagnostics\//,
    );
  });

  test("deletes a diagnostic attachment when issue creation fails", async () => {
    const { hourlyReleases, hourlyReservations, mock } = environment();
    const attachments = attachmentStorage();
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: encodedDiagnosticsZip(),
      }),
      mock,
      async () => {
        throw new Error("simulated GitHub failure");
      },
      mock.FEEDBACK_RATE_LIMITER,
      attachments.namespace,
    );

    expect(response.status).toBe(502);
    expect(attachments.archives.size).toBe(0);
    expect(hourlyReleases).toEqual([
      {
        hour: hourlyReservations[0]?.hour,
        key: hourlyReservations[0]?.key,
      },
    ]);
  });

  test("retains diagnostics and the rate-limit slot when issue creation may have succeeded", async () => {
    const { hourlyReleases, hourlyReservations, mock } = environment();
    const attachments = attachmentStorage();
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: encodedDiagnosticsZip(),
      }),
      mock,
      async () => {
        throw new AmbiguousIssueCreationError(
          "simulated lost GitHub response",
        );
      },
      mock.FEEDBACK_RATE_LIMITER,
      attachments.namespace,
    );

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({
      error: "Feedback may have been submitted. Check GitHub before trying again.",
    });
    expect(attachments.archives.size).toBe(1);
    expect(hourlyReservations).toHaveLength(1);
    expect(hourlyReleases).toHaveLength(0);
  });

  test("returns 503 without reserving a slot when attachment storage is unavailable", async () => {
    const { hourlyReservations, mock } = environment();
    let createdIssue = false;
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: encodedDiagnosticsZip(),
      }),
      mock,
      async () => {
        createdIssue = true;
        return { html_url: "https://github.com/example/issues/42", number: 42 };
      },
      mock.FEEDBACK_RATE_LIMITER,
    );

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({
      error: "Feedback is temporarily unavailable. Please try again.",
    });
    expect(hourlyReservations).toHaveLength(0);
    expect(createdIssue).toBe(false);
  });

  test("rejects malformed diagnostic archives", async () => {
    const { mock } = environment();
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: btoa("not a zip"),
      }),
      mock,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "Invalid diagnostic archive.",
    });
  });

  test("rejects truncated ZIP data despite a valid local-header signature", async () => {
    const { mock } = environment();
    const truncated = diagnosticsZip().slice(0, -10);
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: Buffer.from(truncated).toString("base64"),
      }),
      mock,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "Invalid diagnostic archive.",
    });
  });

  test("rejects path-overriding and unknown ZIP extra fields", async () => {
    const { mock } = environment();
    const unicodePathOverride = extraField(
      0x7075,
      new TextEncoder().encode("Dayline Diagnostics/README.txt"),
    );
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: encodedDiagnosticsZip([
          {
            path: "Dayline Diagnostics/README.txt",
            data: new TextEncoder().encode("readme"),
            centralExtra: unicodePathOverride,
            localExtra: unicodePathOverride,
          },
        ]),
      }),
      mock,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "Invalid diagnostic archive.",
    });
  });

  test.each([
    {
      name: "prefix",
      archive: diagnosticsZip(undefined, {
        prefix: new Uint8Array([0]),
      }),
    },
    {
      name: "gap before the central directory",
      archive: diagnosticsZip(undefined, {
        gapBeforeCentral: new Uint8Array([0]),
      }),
    },
    {
      name: "unreferenced local record",
      archive: diagnosticsZip(undefined, {
        unreferencedEntries: [
          {
            path: "Dayline Diagnostics/Logs/dayline.log",
            data: new TextEncoder().encode("hidden"),
          },
        ],
      }),
    },
  ])("rejects hidden ZIP data: $name", async ({ archive }) => {
    const { mock } = environment();
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: Buffer.from(archive).toString("base64"),
      }),
      mock,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "Invalid diagnostic archive.",
    });
  });

  test("rejects a forged CRC despite matching local and central records", async () => {
    const { mock } = environment();
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: encodedDiagnosticsZip([
          {
            path: "Dayline Diagnostics/README.txt",
            data: new TextEncoder().encode("readme"),
            checksum: 0,
          },
        ]),
      }),
      mock,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "Invalid diagnostic archive.",
    });
  });

  test("rejects forged deflate metadata after streaming the real content", async () => {
    const { mock } = environment();
    const content = new TextEncoder().encode("Dayline diagnostics");
    const compressedData = await deflateRaw(content);
    const archive = diagnosticsZip([
      {
        path: "Dayline Diagnostics/README.txt",
        data: content,
        compressedData,
        method: 8,
        uncompressedSize: content.byteLength - 1,
      },
    ]);
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: Buffer.from(archive).toString("base64"),
      }),
      mock,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "Invalid diagnostic archive.",
    });
  });

  test("aborts an actual deflate bomb beyond the per-entry stream limit", async () => {
    const { mock } = environment();
    const expandedContent = new Uint8Array(8 * 1024 * 1024 + 1);
    const compressedData = await deflateRaw(expandedContent);
    const archive = diagnosticsZip([
      {
        path: "Dayline Diagnostics/README.txt",
        data: expandedContent,
        compressedData,
        method: 8,
        uncompressedSize: 1,
      },
    ]);
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: Buffer.from(archive).toString("base64"),
      }),
      mock,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "Invalid diagnostic archive.",
    });
  });

  test("aborts deflated content beyond the aggregate stream limit", async () => {
    const { mock } = environment();
    const expandedContent = new Uint8Array(7 * 1024 * 1024);
    const compressedData = await deflateRaw(expandedContent);
    const entries = [
      "Dayline Diagnostics/README.txt",
      ...Array.from(
        { length: 3 },
        (_, index) =>
          `Dayline Diagnostics/Crash Reports/Dayline-${index}.ips`,
      ),
    ].map((path) => ({
      path,
      data: expandedContent,
      compressedData,
      method: 8,
      uncompressedSize: 1,
    }));
    const archive = diagnosticsZip(entries);
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: Buffer.from(archive).toString("base64"),
      }),
      mock,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "Invalid diagnostic archive.",
    });
  });

  test.each([
    {
      name: "path traversal",
      entries: [
        {
          path: "Dayline Diagnostics/README.txt",
          data: new TextEncoder().encode("readme"),
        },
        { path: "Dayline Diagnostics/../secret.txt" },
      ],
    },
    {
      name: "absolute path",
      entries: [{ path: "/Dayline Diagnostics/README.txt" }],
    },
    {
      name: "backslash path",
      entries: [{ path: "Dayline Diagnostics\\README.txt" }],
    },
    {
      name: "missing required README",
      entries: [{ path: "Dayline Diagnostics/Logs/dayline.log" }],
    },
    {
      name: "symlink",
      entries: [
        {
          path: "Dayline Diagnostics/README.txt",
          data: new TextEncoder().encode("target"),
          madeBy: 0x0314,
          externalAttributes: 0xa1ff0000,
        },
      ],
    },
    {
      name: "encryption",
      entries: [
        {
          path: "Dayline Diagnostics/README.txt",
          data: new TextEncoder().encode("encrypted"),
          flags: 1,
        },
      ],
    },
    {
      name: "unsupported compression",
      entries: [
        {
          path: "Dayline Diagnostics/README.txt",
          data: new Uint8Array([1]),
          method: 12,
          uncompressedSize: 1,
        },
      ],
    },
    {
      name: "extreme compression ratio",
      entries: [
        {
          path: "Dayline Diagnostics/README.txt",
          data: new Uint8Array([1]),
          method: 8,
          uncompressedSize: 1_000_000,
        },
      ],
    },
    {
      name: "oversized uncompressed entry",
      entries: [
        {
          path: "Dayline Diagnostics/README.txt",
          data: new Uint8Array(50_000),
          method: 8,
          uncompressedSize: 8 * 1024 * 1024 + 1,
        },
      ],
    },
    {
      name: "oversized total uncompressed content",
      entries: [
        {
          path: "Dayline Diagnostics/README.txt",
          data: new TextEncoder().encode("readme"),
        },
        ...Array.from({ length: 4 }, (_, index) => ({
          path: `Dayline Diagnostics/Crash Reports/Dayline-${index}.ips`,
          data: new Uint8Array(40_000),
          method: 8,
          uncompressedSize: 7 * 1024 * 1024,
        })),
      ],
    },
    {
      name: "excessive entry count",
      entries: [
        {
          path: "Dayline Diagnostics/README.txt",
          data: new TextEncoder().encode("readme"),
        },
        ...Array.from({ length: 64 }, (_, index) => ({
          path: `Dayline Diagnostics/Crash Reports/Dayline-${index}.ips`,
        })),
      ],
    },
  ])("rejects unsafe or pathological ZIP archives: $name", async ({ entries }) => {
    const { mock } = environment();
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: encodedDiagnosticsZip(entries),
      }),
      mock,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "Invalid diagnostic archive.",
    });
  });

  test("rejects ZIP64 markers", async () => {
    const { mock } = environment();
    const archive = diagnosticsZip();
    const view = new DataView(
      archive.buffer,
      archive.byteOffset,
      archive.byteLength,
    );
    view.setUint16(archive.byteLength - 22 + 10, 0xffff, true);
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: Buffer.from(archive).toString("base64"),
      }),
      mock,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "Invalid diagnostic archive.",
    });
  });

  test("rejects spoofed system information", async () => {
    const { mock } = environment();
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "other",
        message: "This is long enough to submit.",
        metadata: {
          appVersion: "0.1.8",
          build: "33",
          macOSVersion: "Robin's MacBook",
          architecture: "Apple Silicon",
        },
      }),
      mock,
      async () => {
        throw new Error("must not create an issue");
      },
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "Invalid anonymous system information.",
    });
  });

  test("enforces the anonymous hourly limit", async () => {
    const { mock } = environment({ hourlyAllowed: false });
    const response = await handleFeedbackRequest(
      feedbackRequest({ category: "bug", message: "This is a valid report." }),
      mock,
    );

    expect(response.status).toBe(429);
    expect(response.headers.get("Retry-After")).toBe("3600");
  });

  test("rejects a streamed oversized body before buffering it", async () => {
    const { mock } = environment();
    const encoder = new TextEncoder();
    const request = new Request("https://dayline.robin.build/api/feedback", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Dayline-Client": "macOS",
        "CF-Connecting-IP": "192.0.2.1",
      },
      body: new ReadableStream({
        start(controller) {
          controller.enqueue(encoder.encode("x".repeat(2_100_001)));
          controller.close();
        },
      }),
    });

    const response = await handleFeedbackRequest(request, mock);

    expect(response.status).toBe(413);
  });

  test("fails closed when the hourly limiter is unavailable", async () => {
    const { burstKeys, mock } = environment({ hourlyLimitFails: true });
    let createdIssue = false;
    const response = await handleFeedbackRequest(
      feedbackRequest({ category: "other", message: "This is valid feedback." }),
      mock,
      async () => {
        createdIssue = true;
        return { html_url: "https://github.com/example/issues/42", number: 42 };
      },
    );

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({
      error: "Feedback is temporarily unavailable. Please try again.",
    });
    expect(burstKeys).toHaveLength(1);
    expect(createdIssue).toBe(false);
  });
});

describe("GitHub issue creation outcome", () => {
  test("returns a valid created issue", async () => {
    const issue = await resolveGitHubIssueCreation(async () =>
      Response.json(
        { html_url: "https://github.com/example/issues/42", number: 42 },
        { status: 201 },
      ),
    );

    expect(issue).toEqual({
      html_url: "https://github.com/example/issues/42",
      number: 42,
    });
  });

  test.each([
    ["network failure", async () => Promise.reject(new Error("network lost"))],
    ["GitHub server failure", async () => new Response(null, { status: 503 })],
    ["malformed success", async () => Response.json({}, { status: 201 })],
  ])("classifies %s as ambiguous", async (_name, send) => {
    await expect(resolveGitHubIssueCreation(send)).rejects.toBeInstanceOf(
      AmbiguousIssueCreationError,
    );
  });

  test("classifies a GitHub client failure as definite", async () => {
    const error = await resolveGitHubIssueCreation(async () =>
      new Response(null, { status: 422 }),
    ).catch((caught) => caught);

    expect(error).toBeInstanceOf(Error);
    expect(error).not.toBeInstanceOf(AmbiguousIssueCreationError);
  });
});
