import { describe, expect, test } from "bun:test";
import {
  type FeedbackAttachmentStoreNamespace,
  type FeedbackEnvironment,
  handleFeedbackAttachmentRequest,
  handleFeedbackRequest,
  makeGitHubIssueDraft,
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
      }),
    },
    FEEDBACK_RATE_LIMIT_SECRET: "x",
    GITHUB_APP_ID: "1",
    GITHUB_INSTALLATION_ID: "2",
    GITHUB_PRIVATE_KEY: "",
  };
  return { burstKeys, hourlyReservations, mock };
}

function feedbackRequest(body: unknown) {
  return new Request("https://dayline.robin.build/api/feedback", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Dayline-Client": "macOS",
      "CF-Connecting-IP": "192.0.2.1",
    },
    body: JSON.stringify(body),
  });
}

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
    let diagnosticsURL: string | undefined;
    let capturedDraft: ReturnType<typeof makeGitHubIssueDraft> | undefined;
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: "UEsDBAECAw==",
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
    );
    expect(download.status).toBe(200);
    expect(download.headers.get("Content-Type")).toBe("application/zip");
    expect(download.headers.get("Content-Disposition")).toContain(
      "Dayline-Diagnostics.zip",
    );
    expect(new Uint8Array(await download.arrayBuffer())).toEqual(
      new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0x01, 0x02, 0x03]),
    );
  });

  test("deletes a diagnostic attachment when issue creation fails", async () => {
    const { mock } = environment();
    const attachments = attachmentStorage();
    const response = await handleFeedbackRequest(
      feedbackRequest({
        category: "bug",
        message: "The menu crashed while navigating with the keyboard.",
        diagnosticsArchive: "UEsDBAECAw==",
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
