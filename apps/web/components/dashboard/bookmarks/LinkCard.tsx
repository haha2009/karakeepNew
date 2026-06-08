"use client";

import React from "react";
import Image from "next/image";
import Link from "next/link";
import { formatDistanceToNow } from "date-fns";
import { zhCN } from "date-fns/locale";
import { ExternalLink } from "lucide-react";
import { cn } from "@/lib/utils";
import { useUserSettings } from "@/lib/userSettings";

import type { ZBookmarkTypeLink } from "@karakeep/shared/types/bookmarks";
import {
  getBookmarkLinkImageUrl,
  getSourceUrl,
  isBookmarkStillCrawling,
} from "@karakeep/shared/utils/bookmarkUtils";

import { BookmarkLayoutAdaptingCard } from "./BookmarkLayoutAdaptingCard";
import FooterLinkURL from "./FooterLinkURL";
import { formatStars } from "./GitHubProjectBadge";

const useOnClickUrl = (bookmark: ZBookmarkTypeLink) => {
  const userSettings = useUserSettings();
  return {
    urlTarget:
      userSettings.bookmarkClickAction === "open_original_link"
        ? ("_blank" as const)
        : ("_self" as const),
    onClickUrl:
      userSettings.bookmarkClickAction === "expand_bookmark_preview"
        ? `/dashboard/preview/${bookmark.id}`
        : bookmark.content.url,
  };
};

function LinkTitle({ bookmark }: { bookmark: ZBookmarkTypeLink }) {
  const { onClickUrl, urlTarget } = useOnClickUrl(bookmark);
  const parsedUrl = new URL(bookmark.content.url);
  return (
    <Link href={onClickUrl} target={urlTarget} rel="noreferrer">
      {bookmark.content.title ?? parsedUrl.host}
    </Link>
  );
}

function GitHubTitle({ bookmark }: { bookmark: ZBookmarkTypeLink }) {
  const { onClickUrl, urlTarget } = useOnClickUrl(bookmark);
  const gh = bookmark.githubProject!;
  return (
    <Link
      href={onClickUrl}
      target={urlTarget}
      rel="noreferrer"
      className="inline-flex items-center gap-1.5"
    >
      {gh.name}
      <ExternalLink className="mt-0.5 size-4 shrink-0 text-gray-300 hover:text-gray-500" />
    </Link>
  );
}

function LinkImage({
  bookmark,
  className,
}: {
  bookmark: ZBookmarkTypeLink;
  className?: string;
}) {
  const { onClickUrl, urlTarget } = useOnClickUrl(bookmark);
  const link = bookmark.content;
  const [imgUrl, setImgUrl] = React.useState<string | null>(() => {
    const details = getBookmarkLinkImageUrl(link);
    return details ? details.url : null;
  });
  const [triedFallback, setTriedFallback] = React.useState(false);

  const handleError = React.useCallback(() => {
    if (!triedFallback && link.imageUrl) {
      setTriedFallback(true);
      setImgUrl(link.imageUrl);
    }
  }, [triedFallback, link.imageUrl]);

  const imgComponent = (url: string, unoptimized: boolean) => (
    <Image
      unoptimized={unoptimized}
      className={className}
      alt="card banner"
      fill={true}
      src={url}
      onError={handleError}
    />
  );

  let img: React.ReactNode;
  if (isBookmarkStillCrawling(bookmark)) {
    img = imgComponent("/blur.avif", false);
  } else if (imgUrl) {
    img = imgComponent(imgUrl, true);
  } else {
    img = imgComponent(
      "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAA1JREFUGFdj+P///38ACfsD/QVDRcoAAAAASUVORK5CYII=",
      true,
    );
  }

  return (
    <Link
      href={onClickUrl}
      target={urlTarget}
      rel="noreferrer"
      className={className}
    >
      <div className="relative size-full flex-1">{img}</div>
    </Link>
  );
}

function GitHubImage({
  bookmark,
  className,
}: {
  bookmark: ZBookmarkTypeLink;
  className?: string;
}) {
  const gh = bookmark.githubProject!;
  const { onClickUrl, urlTarget } = useOnClickUrl(bookmark);
  const link = bookmark.content;
  const [ogUrl] = React.useState<string | null>(() => {
    const details = getBookmarkLinkImageUrl(link);
    return details ? details.url : null;
  });
  const [ogError, setOgError] = React.useState(false);
  const [avatarError, setAvatarError] = React.useState(false);

  const avatarUrl = `https://avatars.githubusercontent.com/${gh.owner}?s=400`;
  const useOg = ogUrl && !ogError;
  const useAvatar = !useOg && !avatarError;

  return (
    <Link
        href={onClickUrl}
        target={urlTarget}
        rel="noreferrer"
        className={className}
      >
        <div className="relative size-full">
          {useOg ? (
            <Image
              unoptimized
              src={ogUrl!}
              alt=""
              fill
              className="object-cover"
              onError={() => setOgError(true)}
            />
          ) : useAvatar ? (
            <Image
              unoptimized
              src={avatarUrl}
              alt=""
              fill
              className="object-cover"
              onError={() => setAvatarError(true)}
            />
          ) : (
            <div className="flex size-full items-center justify-center bg-gray-800 p-4">
              <span className="select-none text-center text-lg font-bold text-gray-400">
                {gh.name ?? gh.fullName}
              </span>
            </div>
          )}
          <div className="pointer-events-none absolute bottom-2 right-2">
            <div className="flex items-center gap-2 rounded-md bg-gray-900/30 px-2.5 py-1 text-xs text-white backdrop-blur-md">
              <span className="inline-flex items-center gap-1 font-medium">
                <svg className="size-3.5" viewBox="0 0 16 16" fill="currentColor">
                  <path d="M8 .25a.75.75 0 01.673.418l1.882 3.815 4.21.612a.75.75 0 01.416 1.279l-3.046 2.97.719 4.192a.75.75 0 01-1.088.791L8 12.347l-3.766 1.98a.75.75 0 01-1.088-.79l.72-4.192L.82 6.374a.75.75 0 01.416-1.28l4.21-.611L7.327.668A.75.75 0 018 .25z" />
                </svg>
                {formatStars(gh.stars)}
              </span>
              <span className="text-white/40">·</span>
              <span>
                {gh.pushedAt
                  ? formatDistanceToNow(gh.pushedAt, {
                      locale: zhCN,
                      addSuffix: true,
                    })
                  : "未知"}
              </span>
            </div>
          </div>
        </div>
      </Link>
  );
}

function GitHubContent({ bookmark }: { bookmark: ZBookmarkTypeLink }) {
  const gh = bookmark.githubProject;
  if (!gh) return null;
  const tags = gh.tags?.filter(Boolean) ?? [];
  const summary = gh.humanSummary ?? gh.description;
  return (
    <div className="flex flex-col gap-2">
      {summary && (
        <p className="line-clamp-2 text-sm leading-snug text-gray-500">
          {summary}
        </p>
      )}
      {tags.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {tags.map((tag) => (
            <span
              key={tag}
              className="rounded bg-gray-200 px-2 py-0.5 text-xs font-medium text-gray-700"
            >
              {tag}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

export default function LinkCard({
  bookmark: bookmarkLink,
  className,
  bookmarkIndex,
}: {
  bookmark: ZBookmarkTypeLink;
  className?: string;
  bookmarkIndex?: number;
}) {
  const gh = bookmarkLink.githubProject;

  if (gh) {
    return (
      <BookmarkLayoutAdaptingCard
        title={<GitHubTitle bookmark={bookmarkLink} />}
        content={<GitHubContent bookmark={bookmarkLink} />}
        bookmark={bookmarkLink}
        wrapTags={false}
        image={(layout, className) => (
          <GitHubImage
            className={cn(className, layout !== "list" && "border-b border-gray-200")}
            bookmark={bookmarkLink}
          />
        )}
        className={className}
        bookmarkIndex={bookmarkIndex}
      />
    );
  }

  return (
    <BookmarkLayoutAdaptingCard
      title={<LinkTitle bookmark={bookmarkLink} />}
      footer={<FooterLinkURL url={getSourceUrl(bookmarkLink)} />}
      bookmark={bookmarkLink}
      wrapTags={false}
      image={(_layout, className) => (
        <LinkImage className={className} bookmark={bookmarkLink} />
      )}
      className={className}
      bookmarkIndex={bookmarkIndex}
    />
  );
}
