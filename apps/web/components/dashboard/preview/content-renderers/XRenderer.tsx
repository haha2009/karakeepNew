"use client";

import { ExternalLink, MessageSquare } from "lucide-react";
import { useState } from "react";

import { ZBookmark } from "@karakeep/shared/types/bookmarks";

import { ContentRenderer } from "./types";
import { canRenderLinkType, extractFromUrl } from "./renderer-utils";

const TWEET_ID_PATTERNS = [
  /(?:twitter\.com|x\.com)\/\w+\/status\/(\d+)/,
  /(?:twitter\.com|x\.com)\/i\/web\/status\/(\d+)/,
];

function canRenderX(bookmark: ZBookmark): boolean {
  if (!canRenderLinkType(bookmark)) return false;
  return extractFromUrl(bookmark.content.url, TWEET_ID_PATTERNS) !== null;
}

function XRendererComponent({ bookmark }: { bookmark: ZBookmark }) {
  const tweetUrl = bookmark.content.type === "link" ? bookmark.content.url : "";
  const tweetId = extractFromUrl(tweetUrl, TWEET_ID_PATTERNS);
  const [loadError, setLoadError] = useState(false);

  if (!tweetId) return null;

  if (loadError) {
    return (
      <div className="flex h-full w-full flex-col items-center justify-center gap-3 p-4 text-center">
        <p className="text-muted-foreground">Failed to load tweet embed.</p>
        <a
          href={tweetUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1.5 text-sm text-foreground underline"
        >
          <ExternalLink className="h-4 w-4" />
          View on X
        </a>
      </div>
    );
  }

  return (
    <div className="flex h-full w-full flex-col items-center overflow-auto p-4">
      <iframe
        src={`https://platform.twitter.com/embed/Tweet.html?id=${tweetId}&theme=light`}
        className="w-full max-w-[550px] flex-1"
        style={{ border: 0, minHeight: 400 }}
        title="X/Twitter Embed"
        loading="lazy"
        sandbox="allow-scripts allow-same-origin allow-popups"
        onError={() => setLoadError(true)}
      />
      <a
        href={tweetUrl}
        target="_blank"
        rel="noopener noreferrer"
        className="mt-2 inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
      >
        <ExternalLink className="h-4 w-4" />
        View on X
      </a>
    </div>
  );
}

export const xRenderer: ContentRenderer = {
  id: "x",
  name: "X (Twitter)",
  icon: MessageSquare,
  canRender: canRenderX,
  component: XRendererComponent,
  priority: 10,
};
