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
    ({ submission, diagnosticsArchive } = validateSubmission(JSON.parse(rawBody)));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invalid feedback.";
    return jsonResponse({ error: message }, 400);
  }

  try {
    if (!rateLimiter) {
      throw new Error("Feedback rate limiter is unavailable.");
    }
    const hour = Math.floor(Date.now() / 3_600_000);
    const reserved = await rateLimiter
      .getByName(clientKey)
      .reserve(hour, hourlySubmissionLimit);
    if (!reserved) {
      return rateLimitedResponse();
    }
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
      if (!attachmentStore) {
        throw new Error("Feedback attachment storage is unavailable.");
      }
      attachmentID = crypto.randomUUID();
      attachment = attachmentStore.getByName(attachmentStoreShard(attachmentID));
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

  const archive = await attachmentStore
    .getByName(attachmentStoreShard(attachmentID))
    .read(attachmentID);
  if (!archive) {
    return jsonResponse({ error: "Diagnostic archive not found." }, 404);
  }

  return new Response(archive, {
    headers: {
      "Cache-Control": "no-store",
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

function validateSubmission(value: unknown): {
  submission: FeedbackSubmission;
  diagnosticsArchive?: ArrayBuffer;
} {
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

  return {
    submission: {
      category: candidate.category as FeedbackCategory,
      message,
      metadata:
        candidate.metadata === undefined
          ? undefined
          : validateMetadata(candidate.metadata),
    },
    diagnosticsArchive:
      candidate.diagnosticsArchive === undefined
        ? undefined
        : validateDiagnosticsArchive(candidate.diagnosticsArchive),
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

function validateDiagnosticsArchive(value: unknown): ArrayBuffer {
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
  validateDiagnosticsZipStructure(archive);
  return archive.buffer as ArrayBuffer;
}

/**
 * Validates the ZIP records we accept without extracting attacker-controlled data.
 * Field offsets follow PKWARE's APPNOTE local header, central directory, and EOCD
 * layouts. Dayline diagnostics use only stored or deflated, non-ZIP64 entries.
 */
function validateDiagnosticsZipStructure(archive: Uint8Array): void {
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

  const decoder = new TextDecoder("utf-8", { fatal: true });
  const localRanges: Array<{ start: number; end: number }> = [];
  let cursor = centralDirectoryOffset;
  let totalUncompressedBytes = 0;
  let hasReadme = false;
  const paths = new Set<string>();

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
    validateExtraFields(view, centralExtraStart, extraLength);

    let path: string;
    try {
      path = decoder.decode(
        archive.subarray(cursor + 46, cursor + 46 + nameLength),
      );
    } catch {
      throw new Error("Invalid diagnostic archive.");
    }
    validateDiagnosticsPath(path);
    if (paths.has(path)) {
      throw new Error("Invalid diagnostic archive.");
    }
    paths.add(path);

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
      totalUncompressedBytes + uncompressedSize >
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
    totalUncompressedBytes += uncompressedSize;
    hasReadme ||= path === "Dayline Diagnostics/README.txt";

    if (
      localHeaderOffset + 30 > centralDirectoryOffset ||
      readUint32(view, localHeaderOffset) !== 0x04034b50 ||
      readUint16(view, localHeaderOffset + 4) > 20
    ) {
      throw new Error("Invalid diagnostic archive.");
    }
    const localFlags = readUint16(view, localHeaderOffset + 6);
    const localMethod = readUint16(view, localHeaderOffset + 8);
    const localCRC32 = readUint32(view, localHeaderOffset + 14);
    const localCompressedSize = readUint32(view, localHeaderOffset + 18);
    const localUncompressedSize = readUint32(view, localHeaderOffset + 22);
    const localNameLength = readUint16(view, localHeaderOffset + 26);
    const localExtraLength = readUint16(view, localHeaderOffset + 28);
    const localNameStart = localHeaderOffset + 30;
    const localExtraStart = localNameStart + localNameLength;
    const dataStart = localExtraStart + localExtraLength;
    const dataEnd = dataStart + compressedSize;
    let localRecordEnd = dataEnd;

    if (
      localFlags !== flags ||
      localMethod !== method ||
      localNameLength !== nameLength ||
      localExtraStart + localExtraLength > centralDirectoryOffset ||
      dataEnd > centralDirectoryOffset ||
      !equalBytes(
        archive.subarray(localNameStart, localNameStart + localNameLength),
        archive.subarray(cursor + 46, cursor + 46 + nameLength),
      )
    ) {
      throw new Error("Invalid diagnostic archive.");
    }
    if ((flags & 0x0008) === 0) {
      if (
        localCRC32 !== crc32 ||
        localCompressedSize !== compressedSize ||
        localUncompressedSize !== uncompressedSize
      ) {
        throw new Error("Invalid diagnostic archive.");
      }
    } else {
      if (
        (localCRC32 !== 0 && localCRC32 !== crc32) ||
        (localCompressedSize !== 0 &&
          localCompressedSize !== compressedSize) ||
        (localUncompressedSize !== 0 &&
          localUncompressedSize !== uncompressedSize)
      ) {
        throw new Error("Invalid diagnostic archive.");
      }
      const hasSignature = readUint32(view, dataEnd) === 0x08074b50;
      const descriptorStart = dataEnd + (hasSignature ? 4 : 0);
      if (
        readUint32(view, descriptorStart) !== crc32 ||
        readUint32(view, descriptorStart + 4) !== compressedSize ||
        readUint32(view, descriptorStart + 8) !== uncompressedSize
      ) {
        throw new Error("Invalid diagnostic archive.");
      }
      localRecordEnd = descriptorStart + 12;
      if (localRecordEnd > centralDirectoryOffset) {
        throw new Error("Invalid diagnostic archive.");
      }
    }
    validateExtraFields(view, localExtraStart, localExtraLength);
    localRanges.push({ start: localHeaderOffset, end: localRecordEnd });
    cursor = recordEnd;
  }

  localRanges.sort((left, right) => left.start - right.start);
  if (
    cursor !== endOfCentralDirectory ||
    !hasReadme ||
    localRanges.some(
      (range, index) =>
        index > 0 && range.start < (localRanges[index - 1]?.end ?? 0),
    )
  ) {
    throw new Error("Invalid diagnostic archive.");
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

function validateExtraFields(
  view: DataView,
  start: number,
  length: number,
): void {
  const end = start + length;
  let cursor = start;
  while (cursor < end) {
    if (cursor + 4 > end) {
      throw new Error("Invalid diagnostic archive.");
    }
    const fieldID = readUint16(view, cursor);
    const fieldLength = readUint16(view, cursor + 2);
    cursor += 4;
    if (fieldID === 0x0001 || cursor + fieldLength > end) {
      throw new Error("Invalid diagnostic archive.");
    }
    cursor += fieldLength;
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

function equalBytes(left: Uint8Array, right: Uint8Array): boolean {
  return (
    left.byteLength === right.byteLength &&
    left.every((value, index) => value === right[index])
  );
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
