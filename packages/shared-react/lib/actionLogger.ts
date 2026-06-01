type LogLevel = "info" | "warn" | "error";
type LogCategory = "action" | "navigation" | "api" | "error";

const PREFIX = "[Karakeep]";

const levelStyles: Record<LogLevel, string> = {
  info: "color: #3b82f6; font-weight: bold;",
  warn: "color: #f59e0b; font-weight: bold;",
  error: "color: #ef4444; font-weight: bold;",
};

const categoryLabels: Record<LogCategory, string> = {
  action: "ACTION",
  navigation: "NAV",
  api: "API",
  error: "ERROR",
};

function log(
  level: LogLevel,
  category: LogCategory,
  message: string,
  details?: Record<string, unknown>,
) {
  const ts = new Date().toLocaleTimeString("zh-CN", { hour12: false });
  const label = `${PREFIX}[${categoryLabels[category]}]`;
  const style = levelStyles[level];

  if (details && Object.keys(details).length > 0) {
    console.log(`%c${label} ${message}`, style, `[${ts}]`, details);
  } else {
    console.log(`%c${label} ${message}`, style, `[${ts}]`);
  }
}

/** Log a user-initiated action (click, toggle, create, delete, etc.) */
export function logUserAction(
  action: string,
  details?: Record<string, unknown>,
) {
  log("info", "action", action, details);
}

/** Log a route change / page navigation */
export function logNavigation(path: string) {
  log("info", "navigation", `Navigated to: ${path}`);
}

/** Log a tRPC API call with timing */
export function logApiCall(method: string, path: string, duration?: number) {
  const details =
    duration !== undefined
      ? { duration: `${duration.toFixed(0)}ms` }
      : undefined;
  log("info", "api", `${method} ${path}`, details);
}

/** Log an error with optional error object details */
export function logError(message: string, error?: unknown) {
  if (error instanceof Error) {
    log("error", "error", message, {
      message: error.message,
      name: error.name,
    });
  } else if (error !== undefined) {
    log("error", "error", message, { error });
  } else {
    log("error", "error", message);
  }
}
