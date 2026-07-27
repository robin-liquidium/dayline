import { DurableObject } from "cloudflare:workers";

const maximumAttachmentBytes = 1_500_000;
const attachmentLifetimeMilliseconds = 30 * 24 * 60 * 60 * 1_000;

interface ExpirationRow {
  expires_at: number | null;
}

/** Stores explicitly shared diagnostic archives behind unguessable public IDs. */
export class FeedbackAttachmentStore extends DurableObject {
  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS attachments (
          id TEXT PRIMARY KEY,
          archive BLOB NOT NULL,
          expires_at INTEGER NOT NULL
        )
      `);
    });
  }

  async save(id: string, archive: ArrayBuffer): Promise<void> {
    if (archive.byteLength > maximumAttachmentBytes) {
      throw new Error("Diagnostic archive is too large.");
    }
    const expiresAt = Date.now() + attachmentLifetimeMilliseconds;
    this.ctx.storage.sql.exec(
      `INSERT INTO attachments (id, archive, expires_at)
       VALUES (?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         archive = excluded.archive,
         expires_at = excluded.expires_at`,
      id,
      archive,
      expiresAt,
    );
    await this.scheduleNextExpiration();
  }

  async read(id: string): Promise<ArrayBuffer | null> {
    const row = this.ctx.storage.sql
      .exec<{ archive: ArrayBuffer }>(
        "SELECT archive FROM attachments WHERE id = ? AND expires_at > ?",
        id,
        Date.now(),
      )
      .toArray()[0];
    return row?.archive ?? null;
  }

  async remove(id: string): Promise<void> {
    this.ctx.storage.sql.exec("DELETE FROM attachments WHERE id = ?", id);
    await this.scheduleNextExpiration();
  }

  /** Permanently removes public attachments once their 30-day windows close. */
  async alarm(): Promise<void> {
    this.ctx.storage.sql.exec(
      "DELETE FROM attachments WHERE expires_at <= ?",
      Date.now(),
    );
    await this.scheduleNextExpiration();
  }

  private async scheduleNextExpiration(): Promise<void> {
    const next = this.ctx.storage.sql
      .exec<ExpirationRow>(
        "SELECT MIN(expires_at) AS expires_at FROM attachments",
      )
      .toArray()[0]?.expires_at;
    if (next !== null && next !== undefined) {
      await this.ctx.storage.setAlarm(next);
    } else {
      await this.ctx.storage.deleteAlarm();
    }
  }
}
