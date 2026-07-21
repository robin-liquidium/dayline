import {
  createStartHandler,
  defaultStreamHandler,
} from "@tanstack/react-start/server";

export { FeedbackRateLimiter } from "./server/feedback-rate-limiter";

const fetch = createStartHandler(defaultStreamHandler);

export default { fetch };
