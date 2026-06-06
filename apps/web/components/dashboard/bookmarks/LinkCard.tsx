"use client";

import React from "react";
import Image from "next/image";
import Link from "next/link";
import { useUserSettings } from "@/lib/userSettings";

import type { ZBookmarkTypeLink } from "@karakeep/shared/types/bookmarks";
import {
  getBookmarkLinkImageUrl,
  getBookmarkTitle,
  getSourceUrl,
  isBookmarkStillCrawling,
} from "@karakeep/shared/utils/bookmarkUtils";

import { BookmarkLayoutAdaptingCard } from "./BookmarkLayoutAdaptingCard";
import FooterLinkURL from "./FooterLinkURL";
import GitHubProjectBadge from "./GitHubProjectBadge";

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
      {getBookmarkTitle(bookmark) ?? parsedUrl.host}
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
    // No image found
    // A dummy white pixel for when there's no image.
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

export default function LinkCard({
  bookmark: bookmarkLink,
  className,
  bookmarkIndex,
}: {
  bookmark: ZBookmarkTypeLink;
  className?: string;
  bookmarkIndex?: number;
}) {
  return (
    <BookmarkLayoutAdaptingCard
      title={<LinkTitle bookmark={bookmarkLink} />}
      content={
        bookmarkLink.githubProject ? (
          <GitHubProjectBadge project={bookmarkLink.githubProject} />
        ) : undefined
      }
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
