import {
  BookmarkTypes,
  ZBookmark,
  ZBookmarkedLink,
} from "@karakeep/shared/types/bookmarks";

/**
 * Shared guard: checks if the bookmark is a LINK type.
 * Acts as a type predicate so TS narrows `bookmark.content` after the call.
 */
export function canRenderLinkType(
  bookmark: ZBookmark,
): bookmark is ZBookmark & { content: ZBookmarkedLink } {
  return bookmark.content.type === BookmarkTypes.LINK;
}

/**
 * Try a list of regex patterns against a URL and return the first group match.
 */
export function extractFromUrl(url: string, patterns: RegExp[]): string | null {
  for (const pattern of patterns) {
    const match = url.match(pattern);
    if (match) return match[1];
  }
  return null;
}
