import { Play } from "lucide-react";

import { ZBookmark } from "@karakeep/shared/types/bookmarks";

import { ContentRenderer } from "./types";
import { canRenderLinkType, extractFromUrl } from "./renderer-utils";

const VIDEO_ID_PATTERNS = [
  /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([^&\n?#]+)/,
  /youtube\.com\/v\/([^&\n?#]+)/,
  /youtube\.com\/shorts\/([^&\n?#]+)/,
];

function canRenderYouTube(bookmark: ZBookmark): boolean {
  if (!canRenderLinkType(bookmark)) return false;
  return extractFromUrl(bookmark.content.url, VIDEO_ID_PATTERNS) !== null;
}

function YouTubeRendererComponent({ bookmark }: { bookmark: ZBookmark }) {
  const videoId =
    bookmark.content.type === "link"
      ? extractFromUrl(bookmark.content.url, VIDEO_ID_PATTERNS)
      : null;
  if (!videoId) return null;

  const embedUrl = `https://www.youtube.com/embed/${videoId}`;

  return (
    <div className="relative h-full w-full overflow-hidden">
      <div className="absolute inset-0 h-full w-full">
        <iframe
          src={embedUrl}
          title="YouTube video player"
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
          allowFullScreen
          className="h-full w-full border-0"
        />
      </div>
    </div>
  );
}

export const youTubeRenderer: ContentRenderer = {
  id: "youtube",
  name: "YouTube",
  icon: Play,
  canRender: canRenderYouTube,
  component: YouTubeRendererComponent,
  priority: 10,
};
