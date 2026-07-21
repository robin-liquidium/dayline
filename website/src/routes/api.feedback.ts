import { createFileRoute } from "@tanstack/react-router";
import { env } from "cloudflare:workers";
import {
  type FeedbackEnvironment,
  handleFeedbackRequest,
} from "../server/feedback";

export const Route = createFileRoute("/api/feedback")({
  server: {
    handlers: {
      POST: ({ request }) =>
        handleFeedbackRequest(request, env as unknown as FeedbackEnvironment),
    },
  },
});
