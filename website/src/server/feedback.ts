const githubOwner = "robin-liquidium";
const githubRepository = "dayline";
const githubApiVersion = "2022-11-28";
const maximumMessageLength = 5_000;
const maximumRequestBytes = 2_100_000;
const maximumDiagnosticsBytes = 1_500_000;
const maximumDiagnosticsEntries = 64;
const maximumDiagnosticsEntryBytes = 8 * 1024 * 1024;
const maximumDiagnosticsUncompressedBytes = 25 * 1024 * 1024;
const maximumDiagnosticsCompressionRatio = 200;
const hourlySubmissionLimit = 3;
const canonicalWebsiteOrigin = "https://dayline.robin.build";

type FeedbackCategory = "bug" | "feature" | "other";

interface FeedbackMetadata {
  appVersion: string;
  build: string;
  macOSVersion: string;
  architecture: "Apple Silicon" | "Intel" | "Unknown";
}

export interface FeedbackSubmission {
  category: FeedbackCategory;
  message: string;
  metadata?: FeedbackMetadata;
  diagnosticsURL?: string;
}

interface RateLimitBinding {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

interface FeedbackRateLimiterStub {
  reserve(hour: number, limit: number): Promise<boolean>;
  release(hour: number): Promise<void>;
}

export interface FeedbackRateLimiterNamespace {
  getByName(name: string): FeedbackRateLimiterStub;
}

interface FeedbackAttachmentStoreStub {
  save(id: string, archive: ArrayBuffer): Promise<void>;
  read(id: string): Promise<ArrayBuffer | null>;
  remove(id: string): Promise<void>;
}

export interface FeedbackAttachmentStoreNamespace {
  getByName(name: string): FeedbackAttachmentStoreStub;
}

export interface FeedbackRequestContext {
  feedbackRateLimiter: FeedbackRateLimiterNamespace;
  feedbackAttachmentStore: FeedbackAttachmentStoreNamespace;
}

export interface FeedbackEnvironment {
  FEEDBACK_RATE_LIMIT: RateLimitBinding;
  FEEDBACK_RATE_LIMITER?: FeedbackRateLimiterNamespace;
  FEEDBACK_RATE_LIMIT_SECRET: string;
  GITHUB_APP_ID: string;
  GITHUB_INSTALLATION_ID: string;
  /** PKCS#8 PEM, converted from GitHub's downloaded PKCS#1 key before upload. */
  GITHUB_PRIVATE_KEY: string;
}

export interface FeedbackAttachmentEnvironment {
  FEEDBACK_RATE_LIMIT: RateLimitBinding;
  FEEDBACK_RATE_LIMIT_SECRET: string;
}

interface GitHubIssue {
  html_url: string;
  number: number;
}

export interface GitHubIssueDraft {
  title: string;
  body: string;
  labels: string[];
}

type IssueCreator = (
  submission: FeedbackSubmission,
  environment: FeedbackEnvironment,
) => Promise<GitHubIssue>;

/** Handles one native Dayline feedback submission and any explicitly included attachment. */
export async function handleFeedbackRequest(
  request: Request,
  environment: FeedbackEnvironment,
  createIssue: IssueCreator = createGitHubIssue,
  rateLimiter: FeedbackRateLimiterNamespace | undefined = environment.FEEDBACK_RATE_LIMITER,
  attachmentStore?: FeedbackAttachmentStoreNamespace,
): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405, {
      Allow: "POST",
    });
  }

  if (request.headers.get("X-Dayline-Client") !== "macOS") {
    return jsonResponse({ error: "Invalid client." }, 403);
  }

  if (!request.headers.get("Content-Type")?.startsWith("application/json")) {
    return jsonResponse({ error: "Expected a JSON request." }, 415);
  }

  const declaredLength = Number(request.headers.get("Content-Length") ?? "0");
  if (declaredLength > maximumRequestBytes) {
    return jsonResponse({ error: "Feedback is too large." }, 413);
  }

  const clientAddress = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const clientKey = await anonymousClientKey(
    clientAddress,
    environment.FEEDBACK_RATE_LIMIT_SECRET,
  );
  const burstLimit = await environment.FEEDBACK_RATE_LIMIT.limit({
    key: clientKey,
  });
  if (!burstLimit.success) {
    return rateLimitedResponse();
  }

  let rawBody: string;
  try {
    rawBody = await readLimitedText(request, maximumRequestBytes);
  } catch (error) {
    if (error instanceof FeedbackBodyTooLargeError) {
      return jsonResponse({ error: "Feedback is too large." }, 413);
    }
    return jsonResponse({ error: "Could not read feedback." }, 400);
  }

  let submission: FeedbackSubmission;
  let diagnosticsArchive: ArrayBuffer | undefined;
  try {
    ({ submission, diagnosticsArchive } = await validateSubmission(
      JSON.parse(rawBody),
    ));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invalid feedback.";
    return jsonResponse({ error: message }, 400);
  }

  if (diagnosticsArchive && !attachmentStore) {
    console.error("Feedback attachment storage is unavailable.");
    return jsonResponse(
      { error: "Feedback is temporarily unavailable. Please try again." },
      503,
    );
  }

  let hourlyReservation:
    | { limiter: FeedbackRateLimiterStub; hour: number }
    | undefined;
  try {
    if (!rateLimiter) {
      throw new Error("Feedback rate limiter is unavailable.");
    }
    const hour = Math.floor(Date.now() / 3_600_000);
    const limiter = rateLimiter.getByName(clientKey);
    const reserved = await limiter.reserve(hour, hourlySubmissionLimit);
    if (!reserved) {
      return rateLimitedResponse();
    }
    hourlyReservation = { limiter, hour };
  } catch {
    console.error("Feedback rate limiter failed.");
    return jsonResponse(
      { error: "Feedback is temporarily unavailable. Please try again." },
      503,
    );
  }

  let attachment: FeedbackAttachmentStoreStub | undefined;
  let attachmentID: string | undefined;
  try {
    if (diagnosticsArchive) {
      attachmentID = crypto.randomUUID();
      attachment = attachmentStore!.getByName(attachmentStoreShard(attachmentID));
      await attachment.save(attachmentID, diagnosticsArchive);
      submission.diagnosticsURL =
        `${canonicalWebsiteOrigin}/api/feedback/diagnostics/${attachmentID}`;
    }
    const issue = await createIssue(submission, environment);
    return jsonResponse({
      issueURL: issue.html_url,
      issueNumber: issue.number,
    });
  } catch (error) {
    if (attachment && attachmentID) {
      try {
        await attachment.remove(attachmentID);
      } catch {
        console.error("Feedback attachment cleanup failed.");
      }
    }
    if (hourlyReservation) {
      try {
        await hourlyReservation.limiter.release(hourlyReservation.hour);
      } catch {
        console.error("Feedback rate-limit rollback failed.");
      }
    }
    console.error(
      "Feedback issue creation failed.",
      error instanceof Error ? error.message : "Unknown error",
    );
    return jsonResponse(
      { error: "Feedback could not be submitted. Please try again." },
      502,
    );
  }
}

/** Serves one unguessable, explicitly shared diagnostic archive until it expires. */
export async function handleFeedbackAttachmentRequest(
  request: Request,
  attachmentID: string,
  attachmentStore?: FeedbackAttachmentStoreNamespace,
  environment?: FeedbackAttachmentEnvironment,
): Promise<Response> {
  if (request.method !== "GET") {
    return jsonResponse({ error: "Method not allowed." }, 405, { Allow: "GET" });
  }
  if (
    !attachmentStore ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      attachmentID,
    )
  ) {
    return jsonResponse({ error: "Diagnostic archive not found." }, 404);
  }

  if (!environment) {
    console.error("Feedback download rate limiter is unavailable.");
    return jsonResponse(
      { error: "Diagnostic download is temporarily unavailable." },
      503,
    );
  }
  try {
    const clientAddress = request.headers.get("CF-Connecting-IP") ?? "unknown";
    const clientKey = await anonymousClientKey(
      clientAddress,
      environment.FEEDBACK_RATE_LIMIT_SECRET,
    );
    const downloadLimit = await environment.FEEDBACK_RATE_LIMIT.limit({
      key: `diagnostics:${clientKey}`,
    });
    if (!downloadLimit.success) {
      return rateLimitedResponse();
    }
  } catch {
    console.error("Feedback download rate limiter failed.");
    return jsonResponse(
      { error: "Diagnostic download is temporarily unavailable." },
      503,
    );
  }

  const archive = await attachmentStore
    .getByName(attachmentStoreShard(attachmentID))
    .read(attachmentID);
  if (!archive) {
    return jsonResponse({ error: "Diagnostic archive not found." }, 404);
  }

  return new Response(archive, {
    headers: {
      "Cache-Control": "no-store",
      "Content-Length": archive.byteLength.toString(),
      "Content-Disposition": 'attachment; filename="Dayline-Diagnostics.zip"',
      "Content-Type": "application/zip",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

/** Produces the exact public GitHub issue content for a validated submission. */
export function makeGitHubIssueDraft(
  submission: FeedbackSubmission,
): GitHubIssueDraft {
  const categoryLabel = {
    bug: "Bug",
    feature: "Feature request",
    other: "Feedback",
  }[submission.category];

  const firstLine = submission.message.split("\n", 1)[0] ?? "";
  const summary = firstLine
    .replace(/[\\`*_{}\[\]()<>#+.!|~@]/g, " ")
    .replace(/https?:\/\/\S+/gi, "link")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 80);

  const metadata = submission.metadata
    ? [
        "## Anonymous system information",
        "",
        `- Dayline: ${submission.metadata.appVersion} (build ${submission.metadata.build})`,
        `- macOS: ${submission.metadata.macOSVersion}`,
        `- Chip: ${submission.metadata.architecture}`,
        "",
      ].join("\n")
    : "";

  const diagnostics = submission.diagnosticsURL
    ? [
        "## Diagnostics",
        "",
        `[Download the explicitly included diagnostic ZIP](${submission.diagnosticsURL})`,
        "",
        "The public download link expires after 30 days. Native macOS crash reports may contain system and device identifiers, loaded-image information, and process metadata.",
        "",
      ].join("\n")
    : "";

  return {
    title: `[${categoryLabel}] ${summary || "Anonymous Dayline feedback"}`,
    body: [
      "## Feedback",
      "",
      renderInertGitHubText(submission.message),
      "",
      metadata,
      diagnostics,
      "---",
      submission.diagnosticsURL
        ? "Submitted anonymously from Dayline. The diagnostic archive was explicitly included by the submitter; no account, calendar, Linear, note, or token contents are collected by Dayline's own log."
        : "Submitted anonymously from Dayline. No account, calendar, Linear, note, device-name, IP-address, token, or log data is included.",
    ]
      .filter(Boolean)
      .join("\n"),
    labels: [
      "feedback",
      ...(submission.category === "bug"
        ? ["bug"]
        : submission.category === "feature"
          ? ["enhancement"]
          : []),
    ],
  };
}

async function validateSubmission(value: unknown): Promise<{
  submission: FeedbackSubmission;
  diagnosticsArchive?: ArrayBuffer;
}> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid feedback.");
  }

  const candidate = value as Record<string, unknown>;
  if (!(["bug", "feature", "other"] as unknown[]).includes(candidate.category)) {
    throw new Error("Choose a valid feedback type.");
  }

  if (typeof candidate.message !== "string") {
    throw new Error("Enter your feedback.");
  }

  const message = candidate.message
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "")
    .trim();
  if (message.length < 10) {
    throw new Error("Feedback must be at least 10 characters.");
  }
  if (message.length > maximumMessageLength) {
    throw new Error(`Feedback must be ${maximumMessageLength} characters or fewer.`);
  }

  const metadata =
    candidate.metadata === undefined
      ? undefined
      : validateMetadata(candidate.metadata);
  const diagnosticsArchive =
    candidate.diagnosticsArchive === undefined
      ? undefined
      : await validateDiagnosticsArchive(candidate.diagnosticsArchive);
  return {
    submission: {
      category: candidate.category as FeedbackCategory,
      message,
      metadata,
    },
    diagnosticsArchive,
  };
}

class FeedbackBodyTooLargeError extends Error {}

async function readLimitedText(request: Request, maximumBytes: number): Promise<string> {
  if (!request.body) {
    return "";
  }

  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let byteCount = 0;
  let result = "";

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        return result + decoder.decode();
      }

      byteCount += value.byteLength;
      if (byteCount > maximumBytes) {
        await reader.cancel();
        throw new FeedbackBodyTooLargeError();
      }
      result += decoder.decode(value, { stream: true });
    }
  } finally {
    reader.releaseLock();
  }
}

function validateMetadata(value: unknown): FeedbackMetadata {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid anonymous system information.");
  }

  const metadata = value as Record<string, unknown>;
  const shortValue = /^[A-Za-z0-9.+-]{1,32}$/;
  const macOSVersion = /^\d{1,3}\.\d{1,3}\.\d{1,3}$/;

  if (
    typeof metadata.appVersion !== "string" ||
    !shortValue.test(metadata.appVersion) ||
    typeof metadata.build !== "string" ||
    !shortValue.test(metadata.build) ||
    typeof metadata.macOSVersion !== "string" ||
    !macOSVersion.test(metadata.macOSVersion) ||
    !(["Apple Silicon", "Intel", "Unknown"] as unknown[]).includes(
      metadata.architecture,
    )
  ) {
    throw new Error("Invalid anonymous system information.");
  }

  return metadata as unknown as FeedbackMetadata;
}

interface CentralZipEntry {
  path: string;
  flags: number;
  method: number;
  expectedCRC32: number;
  compressedSize: number;
  uncompressedSize: number;
  localHeaderOffset: number;
  isDirectory: boolean;
}

interface ParsedZipEntry extends CentralZipEntry {
  dataStart: number;
  dataEnd: number;
  localEnd: number;
}

async function validateDiagnosticsArchive(value: unknown): Promise<ArrayBuffer> {
  const maximumBase64Length = Math.ceil(maximumDiagnosticsBytes / 3) * 4;
  if (
    typeof value !== "string" ||
    value.length > maximumBase64Length ||
    value.length % 4 !== 0 ||
    !/^[A-Za-z0-9+/]*={0,2}$/.test(value)
  ) {
    throw new Error("Invalid diagnostic archive.");
  }

  let archive: Uint8Array;
  try {
    archive = Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
  } catch {
    throw new Error("Invalid diagnostic archive.");
  }
  if (
    archive.byteLength === 0 ||
    archive.byteLength > maximumDiagnosticsBytes
  ) {
    throw new Error("Invalid diagnostic archive.");
  }
  try {
    const entries = parseDiagnosticsZip(archive);
    await verifyDiagnosticsZipContents(archive, entries);
  } catch {
    throw new Error("Invalid diagnostic archive.");
  }
  return archive.buffer as ArrayBuffer;
}

/**
 * Parses the APPNOTE records without trusting entry contents. Central records
 * define the expected entries; local records must cover the entire local-data
 * region exactly once with no prefix, hidden record, overlap, or gap.
 */
function parseDiagnosticsZip(archive: Uint8Array): ParsedZipEntry[] {
  const view = new DataView(archive.buffer, archive.byteOffset, archive.byteLength);
  const endOfCentralDirectory = findEndOfCentralDirectory(view);
  if (endOfCentralDirectory === undefined) {
    throw new Error("Invalid diagnostic archive.");
  }

  const diskNumber = readUint16(view, endOfCentralDirectory + 4);
  const centralDirectoryDisk = readUint16(view, endOfCentralDirectory + 6);
  const entriesOnDisk = readUint16(view, endOfCentralDirectory + 8);
  const entryCount = readUint16(view, endOfCentralDirectory + 10);
  const centralDirectorySize = readUint32(view, endOfCentralDirectory + 12);
  const centralDirectoryOffset = readUint32(view, endOfCentralDirectory + 16);
  const commentLength = readUint16(view, endOfCentralDirectory + 20);

  if (
    diskNumber !== 0 ||
    centralDirectoryDisk !== 0 ||
    entriesOnDisk !== entryCount ||
    entryCount === 0 ||
    entryCount > maximumDiagnosticsEntries ||
    entryCount === 0xffff ||
    centralDirectorySize === 0xffffffff ||
    centralDirectoryOffset === 0xffffffff ||
    endOfCentralDirectory + 22 + commentLength !== archive.byteLength ||
    centralDirectoryOffset + centralDirectorySize !== endOfCentralDirectory ||
    (endOfCentralDirectory >= 20 &&
      readUint32(view, endOfCentralDirectory - 20) === 0x07064b50)
  ) {
    throw new Error("Invalid diagnostic archive.");
  }

  const centralEntries: CentralZipEntry[] = [];
  let cursor = centralDirectoryOffset;
  let hasReadme = false;
  const paths = new Set<string>();
  const localOffsets = new Set<number>();
  let declaredUncompressedBytes = 0;

  for (let index = 0; index < entryCount; index += 1) {
    if (
      cursor + 46 > endOfCentralDirectory ||
      readUint32(view, cursor) !== 0x02014b50
    ) {
      throw new Error("Invalid diagnostic archive.");
    }

    const madeBy = readUint16(view, cursor + 4);
    const versionNeeded = readUint16(view, cursor + 6);
    const flags = readUint16(view, cursor + 8);
    const method = readUint16(view, cursor + 10);
    const crc32 = readUint32(view, cursor + 16);
    const compressedSize = readUint32(view, cursor + 20);
    const uncompressedSize = readUint32(view, cursor + 24);
    const nameLength = readUint16(view, cursor + 28);
    const extraLength = readUint16(view, cursor + 30);
    const fileCommentLength = readUint16(view, cursor + 32);
    const startingDisk = readUint16(view, cursor + 34);
    const externalAttributes = readUint32(view, cursor + 38);
    const localHeaderOffset = readUint32(view, cursor + 42);
    const recordEnd = cursor + 46 + nameLength + extraLength + fileCommentLength;

    if (
      recordEnd > endOfCentralDirectory ||
      nameLength === 0 ||
      startingDisk !== 0 ||
      compressedSize === 0xffffffff ||
      uncompressedSize === 0xffffffff ||
      localHeaderOffset === 0xffffffff ||
      versionNeeded > 20 ||
      (flags & ~0x080e) !== 0 ||
      (method !== 0 && method !== 8) ||
      (method === 0 && (flags & 0x0006) !== 0)
    ) {
      throw new Error("Invalid diagnostic archive.");
    }

    const centralExtraStart = cursor + 46 + nameLength;
    validateSafeExtraFields(view, centralExtraStart, extraLength, 8);
    const path = decodeZipPath(
      archive.subarray(cursor + 46, cursor + 46 + nameLength),
    );
    validateDiagnosticsPath(path);
    if (paths.has(path) || localOffsets.has(localHeaderOffset)) {
      throw new Error("Invalid diagnostic archive.");
    }
    paths.add(path);
    localOffsets.add(localHeaderOffset);

    const unixMode = madeBy >>> 8 === 3 ? externalAttributes >>> 16 : 0;
    const unixFileType = unixMode & 0xf000;
    if (
      unixFileType === 0xa000 ||
      (unixFileType !== 0 && unixFileType !== 0x4000 && unixFileType !== 0x8000)
    ) {
      throw new Error("Invalid diagnostic archive.");
    }

    const isDirectory = path.endsWith("/");
    if (
      (isDirectory &&
        (compressedSize !== 0 || uncompressedSize !== 0 || method !== 0)) ||
      (unixFileType === 0x4000 && !isDirectory) ||
      (unixFileType === 0x8000 && isDirectory) ||
      uncompressedSize > maximumDiagnosticsEntryBytes ||
      declaredUncompressedBytes + uncompressedSize >
        maximumDiagnosticsUncompressedBytes ||
      (!isDirectory &&
        uncompressedSize > 0 &&
        (compressedSize === 0 ||
          uncompressedSize / compressedSize >
            maximumDiagnosticsCompressionRatio)) ||
      (method === 0 && compressedSize !== uncompressedSize)
    ) {
      throw new Error("Invalid diagnostic archive.");
    }
    declaredUncompressedBytes += uncompressedSize;
    hasReadme ||= path === "Dayline Diagnostics/README.txt";
    centralEntries.push({
      path,
      flags,
      method,
      expectedCRC32: crc32,
      compressedSize,
      uncompressedSize,
      localHeaderOffset,
      isDirectory,
    });
    cursor = recordEnd;
  }

  if (cursor !== endOfCentralDirectory || !hasReadme) {
    throw new Error("Invalid diagnostic archive.");
  }

  const entries = centralEntries.map((entry) =>
    parseLocalZipEntry(archive, view, entry, centralDirectoryOffset),
  );
  const localOrder = [...entries].sort(
    (left, right) => left.localHeaderOffset - right.localHeaderOffset,
  );
  // Dayline uses `ditto --keepParent`; require its local records to tile the archive prefix exactly.
  let expectedOffset = 0;
  for (const entry of localOrder) {
    if (entry.localHeaderOffset !== expectedOffset) {
      throw new Error("Invalid diagnostic archive.");
    }
    expectedOffset = entry.localEnd;
  }
  if (expectedOffset !== centralDirectoryOffset) {
    throw new Error("Invalid diagnostic archive.");
  }
  return entries;
}

function parseLocalZipEntry(
  archive: Uint8Array,
  view: DataView,
  entry: CentralZipEntry,
  centralDirectoryOffset: number,
): ParsedZipEntry {
  const offset = entry.localHeaderOffset;
  if (
    offset + 30 > centralDirectoryOffset ||
    readUint32(view, offset) !== 0x04034b50 ||
    readUint16(view, offset + 4) > 20
  ) {
    throw new Error("Invalid diagnostic archive.");
  }

  const localFlags = readUint16(view, offset + 6);
  const localMethod = readUint16(view, offset + 8);
  const localCRC32 = readUint32(view, offset + 14);
  const localCompressedSize = readUint32(view, offset + 18);
  const localUncompressedSize = readUint32(view, offset + 22);
  const localNameLength = readUint16(view, offset + 26);
  const localExtraLength = readUint16(view, offset + 28);
  const localNameStart = offset + 30;
  const localExtraStart = localNameStart + localNameLength;
  const dataStart = localExtraStart + localExtraLength;
  const dataEnd = dataStart + entry.compressedSize;

  if (
    localFlags !== entry.flags ||
    localMethod !== entry.method ||
    decodeZipPath(
      archive.subarray(localNameStart, localNameStart + localNameLength),
    ) !== entry.path ||
    localExtraStart + localExtraLength > centralDirectoryOffset ||
    dataEnd > centralDirectoryOffset
  ) {
    throw new Error("Invalid diagnostic archive.");
  }
  validateSafeExtraFields(view, localExtraStart, localExtraLength, 12);

  let localEnd = dataEnd;
  if ((entry.flags & 0x0008) === 0) {
    if (
      localCRC32 !== entry.expectedCRC32 ||
      localCompressedSize !== entry.compressedSize ||
      localUncompressedSize !== entry.uncompressedSize
    ) {
      throw new Error("Invalid diagnostic archive.");
    }
  } else {
    if (
      (localCRC32 !== 0 && localCRC32 !== entry.expectedCRC32) ||
      (localCompressedSize !== 0 &&
        localCompressedSize !== entry.compressedSize) ||
      (localUncompressedSize !== 0 &&
        localUncompressedSize !== entry.uncompressedSize)
    ) {
      throw new Error("Invalid diagnostic archive.");
    }
    localEnd = parseDataDescriptor(view, dataEnd, entry);
    if (localEnd > centralDirectoryOffset) {
      throw new Error("Invalid diagnostic archive.");
    }
  }

  return { ...entry, dataStart, dataEnd, localEnd };
}

function parseDataDescriptor(
  view: DataView,
  start: number,
  entry: CentralZipEntry,
): number {
  const matchesAt = (offset: number) =>
    readUint32(view, offset) === entry.expectedCRC32 &&
    readUint32(view, offset + 4) === entry.compressedSize &&
    readUint32(view, offset + 8) === entry.uncompressedSize;
  if (readUint32(view, start) === 0x08074b50 && matchesAt(start + 4)) {
    return start + 16;
  }
  if (matchesAt(start)) {
    return start + 12;
  }
  throw new Error("Invalid diagnostic archive.");
}

async function verifyDiagnosticsZipContents(
  archive: Uint8Array,
  entries: readonly ParsedZipEntry[],
): Promise<void> {
  let actualTotalBytes = 0;
  for (const entry of entries) {
    if (entry.isDirectory) {
      if (entry.expectedCRC32 !== 0) {
        throw new Error("Invalid diagnostic archive.");
      }
      continue;
    }

    const compressedData = archive.slice(entry.dataStart, entry.dataEnd);
    const stream =
      entry.method === 0
        ? new Blob([compressedData]).stream()
        : new Blob([compressedData])
            .stream()
            .pipeThrough(new DecompressionStream("deflate-raw"));
    const reader = stream.getReader();
    let actualEntryBytes = 0;
    let checksum = 0xffffffff;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) {
          break;
        }
        actualEntryBytes += value.byteLength;
        actualTotalBytes += value.byteLength;
        if (
          actualEntryBytes > maximumDiagnosticsEntryBytes ||
          actualTotalBytes > maximumDiagnosticsUncompressedBytes
        ) {
          await reader.cancel();
          throw new Error("Invalid diagnostic archive.");
        }
        checksum = updateCRC32(checksum, value);
      }
    } finally {
      reader.releaseLock();
    }

    if (
      actualEntryBytes !== entry.uncompressedSize ||
      ((checksum ^ 0xffffffff) >>> 0) !== entry.expectedCRC32
    ) {
      throw new Error("Invalid diagnostic archive.");
    }
  }
}

function findEndOfCentralDirectory(view: DataView): number | undefined {
  const minimumOffset = Math.max(0, view.byteLength - 22 - 0xffff);
  for (let offset = view.byteLength - 22; offset >= minimumOffset; offset -= 1) {
    if (readUint32(view, offset) === 0x06054b50) {
      return offset;
    }
  }
  return undefined;
}

function validateSafeExtraFields(
  view: DataView,
  start: number,
  length: number,
  allowedUnixFieldLength: 8 | 12,
): void {
  const end = start + length;
  let cursor = start;
  let foundUnixField = false;
  while (cursor < end) {
    if (cursor + 4 > end) {
      throw new Error("Invalid diagnostic archive.");
    }
    const fieldID = readUint16(view, cursor);
    const fieldLength = readUint16(view, cursor + 2);
    cursor += 4;
    if (
      fieldID !== 0x5855 ||
      foundUnixField ||
      fieldLength !== allowedUnixFieldLength ||
      cursor + fieldLength > end
    ) {
      throw new Error("Invalid diagnostic archive.");
    }
    foundUnixField = true;
    cursor += fieldLength;
  }
}

function decodeZipPath(bytes: Uint8Array): string {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new Error("Invalid diagnostic archive.");
  }
}

function validateDiagnosticsPath(path: string): void {
  const allowed =
    path === "Dayline Diagnostics/" ||
    path === "Dayline Diagnostics/README.txt" ||
    path === "Dayline Diagnostics/Logs/" ||
    path === "Dayline Diagnostics/Logs/dayline.log" ||
    path === "Dayline Diagnostics/Logs/dayline.previous.log" ||
    path === "Dayline Diagnostics/Crash Reports/" ||
    /^Dayline Diagnostics\/Crash Reports\/[^/]+\.ips$/.test(path);
  if (
    !allowed ||
    path.includes("\\") ||
    path.startsWith("/") ||
    /^[A-Za-z]:/.test(path) ||
    /[\u0000-\u001f\u007f]/.test(path) ||
    path.split("/").some((component) => component === "..")
  ) {
    throw new Error("Invalid diagnostic archive.");
  }
}

function readUint16(view: DataView, offset: number): number {
  if (offset < 0 || offset + 2 > view.byteLength) {
    throw new Error("Invalid diagnostic archive.");
  }
  return view.getUint16(offset, true);
}

function readUint32(view: DataView, offset: number): number {
  if (offset < 0 || offset + 4 > view.byteLength) {
    throw new Error("Invalid diagnostic archive.");
  }
  return view.getUint32(offset, true);
}

const crc32Table = Uint32Array.from({ length: 256 }, (_, index) => {
  let value = index;
  for (let bit = 0; bit < 8; bit += 1) {
    value = (value >>> 1) ^ (value & 1 ? 0xedb88320 : 0);
  }
  return value >>> 0;
});

function updateCRC32(checksum: number, bytes: Uint8Array): number {
  let result = checksum;
  for (const byte of bytes) {
    result = (result >>> 8) ^ crc32Table[(result ^ byte) & 0xff]!;
  }
  return result >>> 0;
}

/** Bounds random-read storage amplification while distributing real attachment traffic. */
function attachmentStoreShard(attachmentID: string): string {
  return `feedback-diagnostics-${attachmentID.slice(0, 2).toLowerCase()}`;
}

async function anonymousClientKey(
  clientAddress: string,
  secret: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(clientAddress),
  );
  return toHex(new Uint8Array(digest));
}

async function createGitHubIssue(
  submission: FeedbackSubmission,
  environment: FeedbackEnvironment,
): Promise<GitHubIssue> {
  const appJWT = await createGitHubAppJWT(
    environment.GITHUB_APP_ID,
    environment.GITHUB_PRIVATE_KEY,
  );

  const installationResponse = await fetch(
    `https://api.github.com/app/installations/${environment.GITHUB_INSTALLATION_ID}/access_tokens`,
    {
      method: "POST",
      headers: githubHeaders(appJWT),
    },
  );
  if (!installationResponse.ok) {
    throw new Error(
      `GitHub installation token request returned ${installationResponse.status}.`,
    );
  }

  const installation = (await installationResponse.json()) as { token?: string };
  if (!installation.token) {
    throw new Error("GitHub did not return an installation token.");
  }

  const issueResponse = await fetch(
    `https://api.github.com/repos/${githubOwner}/${githubRepository}/issues`,
    {
      method: "POST",
      headers: {
        ...githubHeaders(installation.token),
        "Content-Type": "application/json",
      },
      body: JSON.stringify(makeGitHubIssueDraft(submission)),
    },
  );
  if (!issueResponse.ok) {
    throw new Error(`GitHub issue request returned ${issueResponse.status}.`);
  }

  return (await issueResponse.json()) as GitHubIssue;
}

async function createGitHubAppJWT(
  appID: string,
  privateKeyPEM: string,
): Promise<string> {
  const issuedAt = Math.floor(Date.now() / 1_000) - 60;
  const header = base64URL(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const payload = base64URL(
    new TextEncoder().encode(
      JSON.stringify({ iat: issuedAt, exp: issuedAt + 540, iss: appID }),
    ),
  );
  const unsignedToken = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemBytes(privateKeyPEM),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedToken),
  );

  return `${unsignedToken}.${base64URL(new Uint8Array(signature))}`;
}

function pemBytes(privateKeyPEM: string): ArrayBuffer {
  const normalized = privateKeyPEM.replace(/\\n/g, "\n");
  const base64 = normalized
    .replace(/-{5}[^-]+-{5}/g, "")
    .replace(/\s/g, "");
  return Uint8Array.from(
    atob(base64),
    (character) => character.charCodeAt(0),
  ).buffer as ArrayBuffer;
}

function githubHeaders(token: string): Record<string, string> {
  return {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${token}`,
    "X-GitHub-Api-Version": githubApiVersion,
    "User-Agent": "dayline-feedback",
  };
}

function base64URL(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function renderInertGitHubText(value: string): string {
  const neutralizedMentions = value.replace(/@/g, "@\u200B");
  return neutralizedMentions
    .split(/\r\n?|\n/)
    .map((line) => `    ${line}`)
    .join("\n");
}

function toHex(value: Uint8Array): string {
  return Array.from(value, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function rateLimitedResponse(): Response {
  return jsonResponse(
    { error: "Too many feedback submissions. Please try again later." },
    429,
    { "Retry-After": "3600" },
  );
}

function jsonResponse(
  body: unknown,
  status = 200,
  headers: Record<string, string> = {},
): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      ...headers,
    },
  });
}
