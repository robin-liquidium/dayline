// The site itself is static files. This Worker only handles the feedback
// relay under /api/feedback and hands every other request to the assets.
import {
  type FeedbackAttachmentStoreNamespace,
  type FeedbackEnvironment,
  type FeedbackRateLimiterNamespace,
  handleFeedbackAttachmentRequest,
  handleFeedbackRequest,
} from "./server/feedback";

export { FeedbackAttachmentStore } from "./server/feedback-attachment-store";
export { FeedbackRateLimiter } from "./server/feedback-rate-limiter";

interface Environment extends FeedbackEnvironment {
  ASSETS: { fetch(request: Request): Promise<Response> };
}

interface ExecutionContext {
  exports: {
    FeedbackAttachmentStore: FeedbackAttachmentStoreNamespace;
    FeedbackRateLimiter: FeedbackRateLimiterNamespace;
  };
}

export default {
  fetch(request: Request, environment: Environment, context: ExecutionContext) {
    // Trailing slashes are ignored, as they were under TanStack Start.
    const pathname = new URL(request.url).pathname.replace(/(.)\/+$/, "$1");

    if (pathname === "/api/feedback") {
      if (request.method !== "POST") {
        return new Response("Method Not Allowed", {
          status: 405,
          headers: { Allow: "POST" },
        });
      }
      return handleFeedbackRequest(
        request,
        environment,
        undefined,
        context.exports.FeedbackRateLimiter,
        context.exports.FeedbackAttachmentStore,
      );
    }

    const attachment = pathname.match(
      /^\/api\/feedback\/diagnostics\/([^/]+)$/,
    );
    if (attachment?.[1]) {
      return handleFeedbackAttachmentRequest(
        request,
        attachment[1],
        context.exports.FeedbackAttachmentStore,
        environment,
      );
    }

    return environment.ASSETS.fetch(request);
  },
};
