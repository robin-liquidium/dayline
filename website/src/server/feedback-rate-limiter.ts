import { DurableObject } from "cloudflare:workers";

interface RateLimitState {
  hour: number;
  count: number;
}

/** Strongly consistent hourly feedback limiter, sharded by anonymized client key. */
export class FeedbackRateLimiter extends DurableObject {
  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS rate_limit (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          hour INTEGER NOT NULL,
          count INTEGER NOT NULL
        )
      `);
    });
  }

  /** Atomically reserves one submission in the supplied UTC hour. */
  async reserve(hour: number, limit: number): Promise<boolean> {
    const state = this.ctx.storage.sql
      .exec<RateLimitState>("SELECT hour, count FROM rate_limit WHERE id = 1")
      .toArray()[0];

    if (state?.hour === hour && state.count >= limit) {
      return false;
    }

    const count = state?.hour === hour ? state.count + 1 : 1;
    this.ctx.storage.sql.exec(
      `INSERT INTO rate_limit (id, hour, count)
       VALUES (1, ?, ?)
       ON CONFLICT(id) DO UPDATE SET hour = excluded.hour, count = excluded.count`,
      hour,
      count,
    );
    await this.ctx.storage.setAlarm((hour + 1) * 60 * 60 * 1000);
    return true;
  }

  /** Releases storage once this rate-limit window can no longer be used. */
  async alarm(): Promise<void> {
    await this.ctx.storage.deleteAll();
  }
}
