import type { Context } from "../index";

const isDev = process.env.NODE_ENV === "development";

const C = {
  reset: "\x1b[0m",
  dim: "\x1b[2m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
  cyan: "\x1b[36m",
  red: "\x1b[31m",
};

const methodColors: Record<string, string> = {
  query: C.blue,
  mutation: C.yellow,
  subscription: C.magenta,
};

export function createLoggingMiddleware() {
  return async function loggingMiddleware<T>(opts: {
    ctx: Context;
    type: "query" | "mutation" | "subscription";
    path: string;
    input: unknown;
    next: () => Promise<T>;
  }): Promise<T> {
    if (!isDev) return opts.next();

    const start = performance.now();
    const result = await opts.next();
    const duration = performance.now() - start;

    const methodColor = methodColors[opts.type] || C.cyan;
    const statusColor = (result as { ok: boolean }).ok ? C.green : C.red;
    const status = (result as { ok: boolean }).ok ? "OK" : "ERR";

    console.log(
      `${C.dim}[tRPC]${C.reset} ${methodColor}${opts.type.toUpperCase()}${C.reset} ${opts.path} ${statusColor}${status}${C.reset} ${C.dim}${duration.toFixed(0)}ms${C.reset}`,
    );

    return result;
  };
}
