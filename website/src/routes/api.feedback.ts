import { createFileRoute } from "@tanstack/react-router";
import { env } from "cloudflare:workers";
import {
  type FeedbackEnvironment,
  type FeedbackRequestContext,
  handleFeedbackRequest,
} from "../server/feedback";

export const Route = createFileRoute("/api/feedback")({
  server: {
    handlers: {
      POST: ({ request, context }) =>
        handleFeedbackRequest(
          request,
          env as unknown as FeedbackEnvironment,
          undefined,
          (context as unknown as FeedbackRequestContext).feedbackRateLimiter,
        ),
    },
  },
});
