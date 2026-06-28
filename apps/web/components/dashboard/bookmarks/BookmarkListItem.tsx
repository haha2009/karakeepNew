"use client";

import React, { useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { useUpdateBookmark } from "@karakeep/shared-react/hooks/bookmarks";
import { formatDistanceToNowStrict } from "date-fns";
import { zhCN } from "date-fns/locale";
import { Globe, Star } from "lucide-react";

import type { ZBookmark } from "@karakeep/shared/types/bookmarks";
import { BookmarkTypes } from "@karakeep/shared/types/bookmarks";
import {
  getBookmarkLinkImageUrl,
  getSourceUrl,
} from "@karakeep/shared/utils/bookmarkUtils";

interface BookmarkListItemProps {
  bookmark: ZBookmark;
}

function getDomain(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}

function getContentPreview(bookmark: ZBookmark): string {
  if (bookmark.content.type === BookmarkTypes.LINK) {
    return bookmark.content.description ?? "";
  }
  if (bookmark.content.type === BookmarkTypes.TEXT) {
    return bookmark.content.text?.slice(0, 160) ?? "";
  }
  if (bookmark.content.type === BookmarkTypes.ASSET) {
    return bookmark.content.fileName ?? "";
  }
  return "";
}

function getTitle(bookmark: ZBookmark): string {
  if (bookmark.content.type === BookmarkTypes.LINK) {
    return bookmark.content.title ?? getSourceUrl(bookmark) ?? "Untitled";
  }
  return bookmark.title ?? "Untitled";
}

export default function BookmarkListItem({ bookmark }: BookmarkListItemProps) {
  const [isFavourited, setIsFavourited] = useState(bookmark.favourited);
  const updateBookmarkMutator = useUpdateBookmark();

  const preview = getContentPreview(bookmark);
  const title = getTitle(bookmark);
  const sourceDomain =
    bookmark.content.type === BookmarkTypes.LINK
      ? getDomain(bookmark.content.url)
      : "";
  const linkHref = `/dashboard/preview/${bookmark.id}`;
  const hasTitle = title !== "Untitled";

  const imageData =
    bookmark.content.type === BookmarkTypes.LINK
      ? getBookmarkLinkImageUrl(bookmark.content)
      : null;
  const imageSrc = imageData
    ? typeof imageData === "string"
      ? imageData
      : imageData.url
    : null;

  const handleToggleFavorite = async (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    const newValue = !isFavourited;
    setIsFavourited(newValue);
    updateBookmarkMutator.mutate({
      bookmarkId: bookmark.id,
      favourited: newValue,
    });
  };

  return (
    <Link
      href={linkHref}
      className="group relative flex gap-4 rounded-2xl border border-border/50 bg-card p-4 pb-10 transition-all duration-200 hover:-translate-y-0.5 hover:border-border/80 hover:shadow-lg hover:shadow-black/5 active:scale-[0.99]"
    >
      {/* Thumbnail */}
      {imageSrc && (
        <div className="relative h-[80px] w-[108px] shrink-0 overflow-hidden rounded-lg bg-muted">
          <Image
            src={imageSrc}
            alt=""
            fill
            className="object-cover transition-transform duration-300 group-hover:scale-[1.05]"
            unoptimized
          />
        </div>
      )}

      {/* Text content */}
      <div className="flex min-w-0 flex-1 flex-col gap-2">
        {/* Title row */}
        <div className="flex items-start gap-2">
          <h3
            className={`line-clamp-2 flex-1 text-[13.5px] font-medium leading-snug ${hasTitle ? "text-foreground" : "text-muted-foreground/40"}`}
          >
            {title}
          </h3>
          {/* Favorite button */}
          <button
            onClick={handleToggleFavorite}
            className={`mt-0.5 shrink-0 rounded-md p-1 transition-all duration-200 ${
              isFavourited
                ? "text-amber-400 hover:bg-amber-50 dark:hover:bg-amber-950/30"
                : "text-muted-foreground/30 hover:bg-accent hover:text-muted-foreground/60"
            }`}
            title={isFavourited ? "取消收藏" : "收藏"}
          >
            <Star
              className={`size-4 transition-all ${isFavourited ? "fill-amber-400 drop-shadow-[0_0_3px_rgba(251,191,36,0.4)]" : ""}`}
            />
          </button>
        </div>

        {/* Preview */}
        {preview && (
          <p className="line-clamp-2 text-[11.5px] leading-[1.55] text-muted-foreground/50">
            {preview}
          </p>
        )}
      </div>

      {/* Bottom bar with domain + time */}
      <div className="absolute inset-x-0 bottom-0 flex h-6 items-center gap-2 rounded-b-2xl bg-black/[0.1] px-4 transition-colors group-hover:bg-black/[0.2]">
        {sourceDomain && (
          <>
            <Globe className="size-3 shrink-0 text-foreground/60" />
            <span className="truncate text-[11px] text-foreground/80">
              {sourceDomain}
            </span>
            <span className="shrink-0 text-foreground/30">·</span>
          </>
        )}
        <span className="shrink-0 text-[11px] text-foreground/80">
          {formatDistanceToNowStrict(bookmark.createdAt, {
            locale: zhCN,
            addSuffix: true,
          })}
        </span>
      </div>
    </Link>
  );
}
