import { describe, expect, it } from "vitest";

import { formatLocalDate, normalizeI18nLanguage } from "./date-format";

describe("normalizeI18nLanguage", () => {
  it("normalizes app language identifiers for Intl", () => {
    expect(normalizeI18nLanguage("pt_BR")).toBe("pt-BR");
    expect(normalizeI18nLanguage("zhtw")).toBe("zh-TW");
  });
});

describe("formatLocalDate", () => {
  const date = new Date("2025-01-05T15:42:00Z");

  it("formats supported locales with localized date and time", () => {
    // Use a date that produces the same result across timezones
    // by using a fixed date string that represents local time
    const localDate = new Date("2025-01-05T15:42:00");
    expect(formatLocalDate(localDate, "PP, p", "en")).toMatch(
      /^\w+ \d{1,2}, \d{4}, \d{1,2}:\d{2} \w{2}$/,
    );
    expect(formatLocalDate(date, "PPP", "fr")).toBe("5 janvier 2025");
  });

  it("lets Intl fall back for structurally valid but unsupported locales", () => {
    expect(() => formatLocalDate(date, "PPP", "zz-ZZ")).not.toThrow();
    expect(formatLocalDate(date, "PPP", "zz-ZZ")).toBe("January 5, 2025");
  });

  it("falls back to the runtime locale for malformed locale tags", () => {
    expect(() => formatLocalDate(date, "PPP", "not_a_locale")).not.toThrow();
    expect(formatLocalDate(date, "PPP", "not_a_locale")).toBe(
      "January 5, 2025",
    );
  });
});
