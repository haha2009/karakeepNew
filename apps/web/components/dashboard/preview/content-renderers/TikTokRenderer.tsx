import { Video } from "lucide-react";

import { ZBookmark } from "@karakeep/shared/types/bookmarks";

import { ContentRenderer } from "./types";
import { canRenderLinkType, extractFromUrl } from "./renderer-utils";

const VIDEO_ID_PATTERNS = [
  /tiktok\.com\/@[^/]+\/video\/(\d+)/,
  /tiktok\.com\/t\/([A-Za-z0-9]+)/,
  /vm\.tiktok\.com\/([A-Za-z0-9]+)/,
  /tiktok\.com\/v\/(\d+)/,
];

function canRenderTikTok(bookmark: ZBookmark): boolean {
  if (!canRenderLinkType(bookmark)) return false;
  return extractFromUrl(bookmark.content.url, VIDEO_ID_PATTERNS) !== null;
}

function TikTokRendererComponent({ bookmark }: { bookmark: ZBookmark }) {
  const videoId =
    bookmark.content.type === "link"
      ? extractFromUrl(bookmark.content.url, VIDEO_ID_PATTERNS)
      : null;
  if (!videoId) return null;

  // TikTok embed URL format
  const embedUrl = `https://www.tiktok.com/embed/v2/${videoId}`;

  return (
    <div className="relative h-full w-full overflow-hidden">
      <div className="absolute inset-0 h-full w-full">
        <iframe
          src={embedUrl}
          title="TikTok video"
          className="h-full w-full border-0"
          allow="encrypted-media"
          sandbox="allow-scripts allow-same-origin allow-popups"
        />
      </div>
    </div>
  );
}

export const tikTokRenderer: ContentRenderer = {
  id: "tiktok",
  name: "TikTok",
  icon: Video,
  canRender: canRenderTikTok,
  component: TikTokRendererComponent,
  priority: 10,
};
