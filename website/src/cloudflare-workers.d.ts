declare module "cloudflare:workers" {
  export const env: Record<string, unknown>;

  export class DurableObject<Environment = unknown> {
    protected ctx: DurableObjectState;
    protected env: Environment;
    constructor(ctx: DurableObjectState, env: Environment);
  }
}

interface DurableObjectSqlStorage {
  exec<Row = Record<string, unknown>>(
    query: string,
    ...bindings: unknown[]
  ): { toArray(): Row[] };
}

interface DurableObjectStorage {
  sql: DurableObjectSqlStorage;
  setAlarm(scheduledTime: number | Date): Promise<void>;
  deleteAll(): Promise<void>;
}

interface DurableObjectState {
  storage: DurableObjectStorage;
  blockConcurrencyWhile<Result>(callback: () => Promise<Result>): Promise<Result>;
}
