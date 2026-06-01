"use client";

import { useCallback } from "react";
import {
  logUserAction,
  logError,
  logNavigation,
  logApiCall,
} from "../lib/actionLogger";

export function useActionLogger() {
  const action = useCallback(
    (name: string, details?: Record<string, unknown>) => {
      logUserAction(name, details);
    },
    [],
  );

  const nav = useCallback((path: string) => {
    logNavigation(path);
  }, []);

  const api = useCallback((method: string, path: string, duration?: number) => {
    logApiCall(method, path, duration);
  }, []);

  const err = useCallback((message: string, error?: unknown) => {
    logError(message, error);
  }, []);

  return { action, nav, api, error: err };
}
