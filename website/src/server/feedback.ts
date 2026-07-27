const githubOwner = "robin-liquidium";
const githubRepository = "dayline";
const githubApiVersion = "2022-11-28";
const maximumMessageLength = 5_000;
const maximumRequestBytes = 2_100_000;
const maximumDiagnosticsBytes = 1_500_000;
const hourlySubmissionLimit = 3;

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
        `${new URL(request.url).origin}/api/feedback/diagnostics/${attachmentID}`;
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
    archive.byteLength > maximumDiagnosticsBytes ||
    archive[0] !== 0x50 ||
    archive[1] !== 0x4b ||
    archive[2] !== 0x03 ||
    archive[3] !== 0x04
  ) {
    throw new Error("Invalid diagnostic archive.");
  }
  return archive.buffer as ArrayBuffer;
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
