import {
  createStartHandler,
  defaultStreamHandler,
} from "@tanstack/react-start/server";
import {
  type FeedbackAttachmentStoreNamespace,
  type FeedbackRateLimiterNamespace,
  type FeedbackRequestContext,
  handleFeedbackAttachmentRequest,
} from "./server/feedback";

export { FeedbackAttachmentStore } from "./server/feedback-attachment-store";
export { FeedbackRateLimiter } from "./server/feedback-rate-limiter";

const startFetch = createStartHandler(defaultStreamHandler);

interface CloudflareExecutionContext {
  exports: {
    FeedbackAttachmentStore: FeedbackAttachmentStoreNamespace;
    FeedbackRateLimiter: FeedbackRateLimiterNamespace;
  };
}

const fetch = (
  request: Request,
  _environment: unknown,
  context: CloudflareExecutionContext,
) => {
  const attachmentMatch = new URL(request.url).pathname.match(
    /^\/api\/feedback\/diagnostics\/([^/]+)$/,
  );
  if (attachmentMatch?.[1]) {
    return handleFeedbackAttachmentRequest(
      request,
      attachmentMatch[1],
      context.exports.FeedbackAttachmentStore,
    );
  }

  return startFetch(request, {
    context: {
      feedbackAttachmentStore: context.exports.FeedbackAttachmentStore,
      feedbackRateLimiter: context.exports.FeedbackRateLimiter,
    } satisfies FeedbackRequestContext as never,
  });
};

export default { fetch };
