import { describe, expect, test } from "bun:test";
import {
  type FeedbackEnvironment,
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
          controller.enqueue(encoder.encode("x".repeat(16_385)));
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
