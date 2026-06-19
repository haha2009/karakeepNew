"use client";

import React from "react";
import Image from "next/image";
import Link from "next/link";
import { format, formatDistanceToNowStrict } from "date-fns";
import { zhCN } from "date-fns/locale";
import { ExternalLink } from "lucide-react";

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
    return bookmark.content.text?.slice(0, 200) ?? "";
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
  const preview = getContentPreview(bookmark);
  const title = getTitle(bookmark);
  const sourceDomain =
    bookmark.content.type === BookmarkTypes.LINK
      ? getDomain(bookmark.content.url)
      : "";

  const linkHref = `/dashboard/preview/${bookmark.id}`;

  return (
    <Link
      href={linkHref}
      className="group flex gap-3 rounded-lg border bg-card p-3 transition-colors hover:bg-accent/50"
    >
      {/* Thumbnail */}
      <div className="relative h-[72px] w-[108px] shrink-0 overflow-hidden rounded-md bg-muted">
        {bookmark.content.type === BookmarkTypes.LINK &&
          (() => {
            const imgData = getBookmarkLinkImageUrl(bookmark.content);
            const src = imgData
              ? typeof imgData === "string"
                ? imgData
                : imgData.url
              : "/placeholder.png";
            return (
              <Image
                src={src}
                alt=""
                fill
                className="object-cover"
                unoptimized
              />
            );
          })()}
        {bookmark.content.type === BookmarkTypes.TEXT && (
          <div className="flex h-full w-full items-center justify-center p-2">
            <span className="line-clamp-3 text-[10px] text-muted-foreground">
              {preview}
            </span>
          </div>
        )}
        {bookmark.content.type === BookmarkTypes.ASSET && (
          <div className="flex h-full w-full items-center justify-center bg-muted-foreground/10">
            <span className="text-[10px] text-muted-foreground">Asset</span>
          </div>
        )}
      </div>

      {/* Content */}
      <div className="flex min-w-0 flex-1 flex-col justify-between">
        <div>
          <div className="flex items-start justify-between gap-2">
            <h3 className="line-clamp-1 text-sm font-medium leading-snug">
              {title}
            </h3>
            <ExternalLink className="size-3 shrink-0 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100" />
          </div>
          {preview && (
            <p className="mt-1 line-clamp-2 text-xs text-muted-foreground">
              {preview}
            </p>
          )}
        </div>
        <div className="mt-1.5 flex items-center gap-2 text-[11px] text-muted-foreground">
          <span>{format(bookmark.createdAt, "yyyy-MM-dd")}</span>
          {sourceDomain && (
            <>
              <span className="text-muted-foreground/50">·</span>
              <span>{sourceDomain}</span>
            </>
          )}
          <span className="text-muted-foreground/50">·</span>
          <span>
            {formatDistanceToNowStrict(bookmark.createdAt, {
              locale: zhCN,
              addSuffix: true,
            })}
          </span>
        </div>
      </div>
    </Link>
  );
}
