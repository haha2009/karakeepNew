"use client";

import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
} from "react";

type Theme = "light" | "dark" | "system";

interface ThemeContextValue {
  theme: Theme;
  setTheme: (theme: Theme) => void;
  resolvedTheme: "light" | "dark";
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

const STORAGE_KEY = "theme";

function getStoredTheme(): Theme {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === "light" || stored === "dark" || stored === "system")
      return stored;
  } catch {
    // localStorage may be unavailable in some environments
  }
  return "system";
}

function getSystemTheme(): "light" | "dark" {
  if (typeof window === "undefined") return "light";
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

function resolveTheme(theme: Theme): "light" | "dark" {
  if (theme === "system") return getSystemTheme();
  return theme;
}

function applyTheme(resolved: "light" | "dark") {
  const root = document.documentElement;
  root.classList.toggle("dark", resolved === "dark");
  root.style.colorScheme = resolved;
}

const DISABLE_TRANSITION_CSS =
  "*,*::before,*::after{-webkit-transition:none!important;-moz-transition:none!important;-o-transition:none!important;transition:none!important}";

function disableTransitions() {
  const style = document.createElement("style");
  style.id = "cb-theme-disable-transition";
  style.textContent = DISABLE_TRANSITION_CSS;
  document.head.appendChild(style);
  // Force a reflow
  window.getComputedStyle(document.body);
}

function enableTransitions() {
  const style = document.getElementById("cb-theme-disable-transition");
  if (style) style.remove();
}

export function ThemeProvider({
  children,
  defaultTheme = "system",
}: {
  children: React.ReactNode;
  defaultTheme?: Theme;
}) {
  const [theme, setThemeState] = useState<Theme>(defaultTheme);
  const [resolvedTheme, setResolvedTheme] = useState<"light" | "dark">("light");
  const [_mounted, setMounted] = useState(false);

  // Initialize from storage on mount (client-side only)
  useEffect(() => {
    const stored = getStoredTheme();
    const resolved = resolveTheme(stored);
    setThemeState(stored);
    setResolvedTheme(resolved);
    applyTheme(resolved);
    setMounted(true);
  }, []);

  // Listen for system theme changes
  useEffect(() => {
    if (typeof window === "undefined") return;
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const handler = () => {
      if (theme === "system") {
        const resolved = getSystemTheme();
        setResolvedTheme(resolved);
        applyTheme(resolved);
      }
    };
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, [theme]);

  const setTheme = useCallback((newTheme: Theme) => {
    disableTransitions();
    try {
      localStorage.setItem(STORAGE_KEY, newTheme);
    } catch {
      // localStorage may be unavailable in some environments
    }
    setThemeState(newTheme);
    const resolved = resolveTheme(newTheme);
    setResolvedTheme(resolved);
    applyTheme(resolved);
    requestAnimationFrame(() => enableTransitions());
  }, []);

  return (
    <ThemeContext.Provider value={{ theme, setTheme, resolvedTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme(): {
  theme: Theme;
  setTheme: (theme: Theme) => void;
  resolvedTheme: "light" | "dark";
} {
  const ctx = useContext(ThemeContext);
  if (!ctx) {
    // Fallback for when used outside ThemeProvider
    return {
      theme: "system",
      // Fallback no-op when used outside ThemeProvider
      setTheme: () => {
        /* no-op */
      },
      resolvedTheme: "light",
    };
  }
  return ctx;
}

export function useToggleTheme() {
  const { theme, setTheme } = useTheme();
  return theme === "dark" ? () => setTheme("light") : () => setTheme("dark");
}
