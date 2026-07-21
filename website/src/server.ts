import {
  createStartHandler,
  defaultStreamHandler,
} from "@tanstack/react-start/server";
import type {
  FeedbackRateLimiterNamespace,
  FeedbackRequestContext,
} from "./server/feedback";

export { FeedbackRateLimiter } from "./server/feedback-rate-limiter";

const startFetch = createStartHandler(defaultStreamHandler);

interface CloudflareExecutionContext {
  exports: {
    FeedbackRateLimiter: FeedbackRateLimiterNamespace;
  };
}

const fetch = (
  request: Request,
  _environment: unknown,
  context: CloudflareExecutionContext,
) => startFetch(request, {
  context: {
    feedbackRateLimiter: context.exports.FeedbackRateLimiter,
  } satisfies FeedbackRequestContext as never,
});

export default { fetch };
