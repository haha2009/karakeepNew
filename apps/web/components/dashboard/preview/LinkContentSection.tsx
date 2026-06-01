import Image from "next/image";
import Link from "next/link";
import { useEffect } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { buttonVariants } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { useSession } from "@/lib/auth/client";
import { Trans, useTranslation } from "@/lib/i18n/client";
import { useReaderSettings } from "@/lib/readerSettings";
import {
  AlertTriangle,
  Archive,
  BookOpen,
  Camera,
  ExpandIcon,
  FileText,
  Info,
  Video,
} from "lucide-react";
import { useQueryState } from "nuqs";
import { ErrorBoundary } from "react-error-boundary";

import {
  BookmarkTypes,
  ZBookmark,
  ZBookmarkedLink,
} from "@karakeep/shared/types/bookmarks";
import { READER_FONT_FAMILIES } from "@karakeep/shared/types/readers";

import { contentRendererRegistry } from "./content-renderers";
import ReaderSettingsPopover from "./ReaderSettingsPopover";
import ReaderView from "./ReaderView";

function CustomRendererErrorFallback({
  error,
  onSwitchToReader,
}: {
  error: Error;
  onSwitchToReader: () => void;
}) {
  return (
    <div className="flex h-full w-full flex-col items-center justify-center gap-4 p-4">
      <Alert variant="destructive" className="max-w-md">
        <AlertTriangle className="h-4 w-4" />
        <AlertTitle>Content Renderer Error</AlertTitle>
        <AlertDescription>
          <p className="mb-2 text-sm">
            The custom content renderer failed to load the content.
          </p>
          <details className="mt-2">
            <summary className="cursor-pointer text-xs">
              Technical details
            </summary>
            <code className="mt-1 block text-xs">{error.message}</code>
          </details>
        </AlertDescription>
      </Alert>
      <button
        onClick={onSwitchToReader}
        className="inline-flex items-center gap-1.5 rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90"
      >
        <BookOpen className="h-4 w-4" />
        Switch to Reader View
      </button>
    </div>
  );
}

function FullPageArchiveSection({ link }: { link: ZBookmarkedLink }) {
  const archiveAssetId =
    link.fullPageArchiveAssetId ?? link.precrawledArchiveAssetId;
  return (
    <iframe
      sandbox=""
      title={link.url}
      src={`/api/assets/${archiveAssetId}`}
      className="relative h-full min-w-full"
    />
  );
}

function ScreenshotSection({ link }: { link: ZBookmarkedLink }) {
  return (
    <div className="relative h-full min-w-full">
      <Image
        alt="screenshot"
        src={`/api/assets/${link.screenshotAssetId}`}
        width={0}
        height={0}
        unoptimized
        sizes="100vw"
        style={{ width: "100%", height: "auto" }}
      />
    </div>
  );
}

function VideoSection({ link }: { link: ZBookmarkedLink }) {
  return (
    <div className="relative h-full w-full overflow-hidden">
      <div className="absolute inset-0 h-full w-full">
        {/* eslint-disable-next-line jsx-a11y/media-has-caption -- captions not (yet) available */}
        <video className="m-auto max-h-full max-w-full" controls>
          <source src={`/api/assets/${link.videoAssetId}`} />
          Not supported by your browser
        </video>
      </div>
    </div>
  );
}

function PDFSection({ link }: { link: ZBookmarkedLink }) {
  return (
    <iframe
      title="PDF Viewer"
      src={`/api/assets/${link.pdfAssetId}`}
      className="relative h-full min-w-full"
    />
  );
}

export default function LinkContentSection({
  bookmark,
}: {
  bookmark: ZBookmark;
}) {
  const { t } = useTranslation();
  const { settings } = useReaderSettings();
  const availableRenderers = contentRendererRegistry.getRenderers(bookmark);
  const defaultSection =
    availableRenderers.length > 0 ? availableRenderers[0].id : "cached";
  const [section, setSection] = useQueryState("section", {
    defaultValue: defaultSection,
  });

  // When the URL has a stale ?section=cached parameter but a custom content
  // renderer is available (e.g., from before the renderer was registered),
  // auto-correct to use the renderer instead of a failed cached view.
  const resolvedSection =
    availableRenderers.length > 0 && section === "cached"
      ? availableRenderers[0].id
      : section;

  // Sync URL to remove the stale parameter
  useEffect(() => {
    if (resolvedSection !== section) {
      setSection(resolvedSection);
    }
  }, [resolvedSection, section, setSection]);

  const { data: session } = useSession();
  const isOwner = session?.user?.id === bookmark.userId;

  if (bookmark.content.type != BookmarkTypes.LINK) {
    throw new Error("Invalid content type");
  }

  let content;

  // Check if current section is a custom renderer
  const customRenderer = availableRenderers.find(
    (r) => r.id === resolvedSection,
  );
  if (customRenderer) {
    const RendererComponent = customRenderer.component;
    content = (
      <ErrorBoundary
        fallbackRender={({ error }) => (
          <CustomRendererErrorFallback
            error={error}
            onSwitchToReader={() => setSection("cached")}
          />
        )}
      >
        <RendererComponent bookmark={bookmark} />
      </ErrorBoundary>
    );
  } else if (resolvedSection === "cached") {
    content = (
      <div className="h-full w-full overflow-y-auto overflow-x-hidden px-3 sm:px-6">
        <ReaderView
          className="mx-auto max-w-3xl"
          style={{
            fontFamily: READER_FONT_FAMILIES[settings.fontFamily],
            fontSize: `${settings.fontSize}px`,
            lineHeight: settings.lineHeight,
          }}
          bookmarkId={bookmark.id}
          readOnly={!isOwner}
        />
      </div>
    );
  } else if (resolvedSection === "archive") {
    content = <FullPageArchiveSection link={bookmark.content} />;
  } else if (resolvedSection === "video") {
    content = <VideoSection link={bookmark.content} />;
  } else if (resolvedSection === "pdf") {
    content = <PDFSection link={bookmark.content} />;
  } else {
    content = <ScreenshotSection link={bookmark.content} />;
  }

  return (
    <div className="flex h-full w-full min-w-0 flex-col items-center overflow-hidden">
      <div className="flex w-full items-center justify-center gap-2 border-b px-3 py-1.5">
        <Select onValueChange={setSection} value={resolvedSection}>
          <SelectTrigger className="w-fit">
            <span className="mr-2">
              <SelectValue />
            </span>
          </SelectTrigger>
          <SelectContent>
            <SelectGroup>
              {/* Custom renderers first */}
              {availableRenderers.map((renderer) => {
                const IconComponent = renderer.icon;
                return (
                  <SelectItem key={renderer.id} value={renderer.id}>
                    <div className="flex items-center">
                      <IconComponent className="mr-2 h-4 w-4" />
                      {renderer.name}
                    </div>
                  </SelectItem>
                );
              })}

              {/* Default renderers */}
              <SelectItem value="cached">
                <div className="flex items-center">
                  <BookOpen className="mr-2 h-4 w-4" />
                  {t("preview.reader_view")}
                </div>
              </SelectItem>
              <SelectItem
                value="screenshot"
                disabled={!bookmark.content.screenshotAssetId}
              >
                <div className="flex items-center">
                  <Camera className="mr-2 h-4 w-4" />
                  {t("common.screenshot")}
                </div>
              </SelectItem>
              <SelectItem value="pdf" disabled={!bookmark.content.pdfAssetId}>
                <div className="flex items-center">
                  <FileText className="mr-2 h-4 w-4" />
                  {t("common.pdf")}
                </div>
              </SelectItem>
              <SelectItem
                value="archive"
                disabled={
                  !bookmark.content.fullPageArchiveAssetId &&
                  !bookmark.content.precrawledArchiveAssetId
                }
              >
                <div className="flex items-center">
                  <Archive className="mr-2 h-4 w-4" />
                  {t("common.archive")}
                </div>
              </SelectItem>
              <SelectItem
                value="video"
                disabled={!bookmark.content.videoAssetId}
              >
                <div className="flex items-center">
                  <Video className="mr-2 h-4 w-4" />
                  {t("common.video")}
                </div>
              </SelectItem>
            </SelectGroup>
          </SelectContent>
        </Select>
        {resolvedSection === "cached" && (
          <>
            <ReaderSettingsPopover />
            <Tooltip>
              <TooltipTrigger>
                <Link
                  href={`/reader/${bookmark.id}`}
                  className={buttonVariants({ variant: "outline" })}
                >
                  <ExpandIcon className="h-4 w-4" />
                </Link>
              </TooltipTrigger>
              <TooltipContent side="bottom">FullScreen</TooltipContent>
            </Tooltip>
          </>
        )}
        {resolvedSection === "archive" && (
          <Tooltip>
            <TooltipTrigger asChild>
              <div className="flex h-10 items-center gap-1 rounded-md border border-blue-500/50 bg-blue-50 px-3 text-blue-700 dark:bg-blue-950 dark:text-blue-300">
                <Info className="h-4 w-4" />
              </div>
            </TooltipTrigger>
            <TooltipContent side="bottom" className="max-w-sm">
              <p className="text-sm">
                <Trans
                  i18nKey="preview.archive_info"
                  components={{
                    1: (
                      <Link
                        prefetch={false}
                        href={`/api/assets/${bookmark.content.fullPageArchiveAssetId ?? bookmark.content.precrawledArchiveAssetId}`}
                        download
                        className="font-medium underline"
                      >
                        link
                      </Link>
                    ),
                  }}
                />
              </p>
            </TooltipContent>
          </Tooltip>
        )}
      </div>
      <div className="min-h-0 w-full min-w-0 flex-1">{content}</div>
    </div>
  );
}
