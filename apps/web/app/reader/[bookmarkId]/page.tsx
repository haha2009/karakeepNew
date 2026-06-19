"use client";

import { Suspense, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import HighlightCard from "@/components/dashboard/highlights/HighlightCard";
import ReaderSettingsPopover from "@/components/dashboard/preview/ReaderSettingsPopover";
import ReaderView from "@/components/dashboard/preview/ReaderView";
import { Button } from "@/components/ui/button";
import { FullPageSpinner } from "@/components/ui/full-page-spinner";
import { Separator } from "@/components/ui/separator";
import { useSession } from "@/lib/auth/client";
import { useReaderSettings } from "@/lib/readerSettings";
import { useQuery } from "@tanstack/react-query";
import {
  HighlighterIcon as Highlight,
  Printer,
  Sparkles,
  X,
} from "lucide-react";

import { useTRPC } from "@karakeep/shared-react/trpc";
import { BookmarkTypes } from "@karakeep/shared/types/bookmarks";
import type { AgentDossier } from "@karakeep/shared/types/bookmarks";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { READER_FONT_FAMILIES } from "@karakeep/shared/types/readers";
import { getBookmarkTitle } from "@karakeep/shared/utils/bookmarkUtils";

export default function ReaderViewPage() {
  const params = useParams<{ bookmarkId: string }>();
  const bookmarkId = params.bookmarkId;

  if (!bookmarkId) {
    return <FullPageSpinner />;
  }

  return <ReaderViewPageContent bookmarkId={bookmarkId} />;
}

function ReaderViewPageContent({ bookmarkId }: { bookmarkId: string }) {
  const api = useTRPC();
  const { data: highlights } = useQuery(
    api.highlights.getForBookmark.queryOptions(
      {
        bookmarkId,
      },
      {
        enabled: !!bookmarkId,
      },
    ),
  );
  const { data: bookmark } = useQuery(
    api.bookmarks.getBookmark.queryOptions(
      {
        bookmarkId,
      },
      {
        enabled: !!bookmarkId,
      },
    ),
  );

  const { data: session } = useSession();
  const router = useRouter();
  const { settings } = useReaderSettings();
  const [showHighlights, setShowHighlights] = useState(false);
  const isOwner = session?.user?.id === bookmark?.userId;

  const onClose = () => {
    if (window.history.length > 1) {
      router.back();
    } else {
      router.push("/dashboard");
    }
  };

  const handlePrint = () => {
    window.print();
  };

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="sticky top-0 z-40 border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60 print:hidden">
        <div className="flex h-14 items-center justify-between px-4">
          <div className="flex items-center gap-2">
            <Button variant="ghost" size="icon" onClick={onClose}>
              <X className="h-4 w-4" />
            </Button>
            <span className="text-sm text-muted-foreground">Reader View</span>
          </div>

          <div className="flex items-center gap-2">
            <Button variant="ghost" size="icon" onClick={handlePrint}>
              <Printer className="h-4 w-4" />
            </Button>

            <ReaderSettingsPopover variant="ghost" />

            <Button
              variant={showHighlights ? "default" : "ghost"}
              size="icon"
              onClick={() => setShowHighlights(!showHighlights)}
            >
              <Highlight className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </header>

      <div className="flex overflow-hidden">
        {/* Mobile backdrop */}
        {showHighlights && (
          <button
            className="fixed inset-0 top-14 z-40 bg-black/50 lg:hidden"
            onClick={() => setShowHighlights(false)}
            onKeyDown={(e) => {
              if (e.key === "Escape") {
                setShowHighlights(false);
              }
            }}
            aria-label="Close highlights sidebar"
          />
        )}

        {/* Main Content */}
        <main
          className={`flex-1 overflow-x-hidden transition-all duration-300 ${showHighlights ? "lg:mr-80" : ""}`}
        >
          <article className="mx-auto max-w-3xl overflow-x-hidden px-4 py-8 sm:px-6">
            {bookmark ? (
              <>
                {/* Article Header */}
                <header className="mb-8 space-y-4">
                  <h1
                    className="font-bold leading-tight"
                    style={{
                      fontFamily: READER_FONT_FAMILIES[settings.fontFamily],
                      fontSize: `${settings.fontSize * 1.8}px`,
                      lineHeight: settings.lineHeight * 0.9,
                    }}
                  >
                    {getBookmarkTitle(bookmark)}
                  </h1>
                  <div className="flex items-center gap-4 text-sm text-muted-foreground">
                    {bookmark.content.type == BookmarkTypes.LINK && (
                      <span>By {bookmark.content.author}</span>
                    )}
                    <Separator orientation="vertical" className="h-4" />
                    <span>8 min</span>
                  </div>
                </header>

                {/* Article Content */}
                <Suspense fallback={<FullPageSpinner />}>
                  <div className="overflow-x-hidden">
                    <ReaderView
                      style={{
                        fontFamily: READER_FONT_FAMILIES[settings.fontFamily],
                        fontSize: `${settings.fontSize}px`,
                        lineHeight: settings.lineHeight,
                      }}
                      bookmarkId={bookmarkId}
                      readOnly={!isOwner}
                      progressBarStyle={{ position: "fixed", top: "3.5rem" }}
                    />
                  </div>
                </Suspense>

                {bookmark.githubProject?.agentDossier && (
                  <AgentDossierSection
                    dossier={
                      bookmark.githubProject.agentDossier as AgentDossier
                    }
                  />
                )}
              </>
            ) : (
              <FullPageSpinner />
            )}
          </article>
        </main>

        {/* Highlights Sidebar */}
        {showHighlights && highlights && (
          <aside className="fixed right-0 top-14 z-50 h-[calc(100vh-3.5rem)] w-full border-l bg-background sm:w-80 lg:z-auto lg:bg-background/95 lg:backdrop-blur lg:supports-[backdrop-filter]:bg-background/60 print:hidden">
            <div className="flex h-full flex-col">
              <div className="border-b p-4">
                <div className="flex items-center justify-between">
                  <h2 className="font-semibold">Highlights</h2>
                  <div className="flex items-center gap-2">
                    <span className="text-sm text-muted-foreground">
                      {highlights.highlights.length} saved
                    </span>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-6 w-6 lg:hidden"
                      onClick={() => setShowHighlights(false)}
                    >
                      <X className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              </div>

              <div className="flex-1 overflow-auto p-4">
                <div className="space-y-4">
                  {highlights.highlights.map((highlight) => (
                    <HighlightCard
                      key={highlight.id}
                      highlight={highlight}
                      clickable={true}
                      readOnly={!isOwner}
                    />
                  ))}
                </div>
              </div>
            </div>
          </aside>
        )}
      </div>
    </div>
  );
}

function AgentDossierSection({ dossier }: { dossier: AgentDossier }) {
  return (
    <section className="mx-auto mt-12 max-w-3xl px-4 sm:px-6">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-lg">
            <Sparkles className="size-5 text-yellow-500" />
            AI Project Analysis
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-6">
          {dossier.oneLiner && (
            <p className="text-lg font-medium text-foreground">
              {dossier.oneLiner}
            </p>
          )}

          {dossier.overview && (
            <div>
              <h4 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                Overview
              </h4>
              <p className="whitespace-pre-line text-sm leading-relaxed text-muted-foreground">
                {dossier.overview}
              </p>
            </div>
          )}

          <div className="grid gap-6 sm:grid-cols-2">
            {dossier.keyFeatures && dossier.keyFeatures.length > 0 && (
              <div>
                <h4 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                  Key Features
                </h4>
                <ul className="space-y-1">
                  {dossier.keyFeatures.map((f, i) => (
                    <li
                      key={i}
                      className="flex items-start gap-2 text-sm text-muted-foreground"
                    >
                      <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-primary" />
                      {f}
                    </li>
                  ))}
                </ul>
              </div>
            )}

            {dossier.techStack && dossier.techStack.length > 0 && (
              <div>
                <h4 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                  Tech Stack
                </h4>
                <div className="flex flex-wrap gap-1.5">
                  {dossier.techStack.map((t, i) => (
                    <Badge key={i} variant="secondary">
                      {t}
                    </Badge>
                  ))}
                </div>
              </div>
            )}
          </div>

          <div className="grid gap-6 sm:grid-cols-2">
            {dossier.useCases && dossier.useCases.length > 0 && (
              <div>
                <h4 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                  Use Cases
                </h4>
                <ul className="space-y-1">
                  {dossier.useCases.map((u, i) => (
                    <li
                      key={i}
                      className="flex items-start gap-2 text-sm text-muted-foreground"
                    >
                      <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-primary" />
                      {u}
                    </li>
                  ))}
                </ul>
              </div>
            )}

            {dossier.alternatives && dossier.alternatives.length > 0 && (
              <div>
                <h4 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                  Alternatives
                </h4>
                <div className="flex flex-wrap gap-1.5">
                  {dossier.alternatives.map((a, i) => (
                    <Badge key={i} variant="outline">
                      {a}
                    </Badge>
                  ))}
                </div>
              </div>
            )}
          </div>

          <div className="flex flex-wrap gap-2">
            {dossier.category && (
              <Badge variant="default">{dossier.category}</Badge>
            )}
            {dossier.maturity && (
              <Badge
                variant={
                  dossier.maturity === "active"
                    ? "default"
                    : dossier.maturity === "stable"
                      ? "secondary"
                      : "outline"
                }
              >
                {dossier.maturity}
              </Badge>
            )}
            {dossier.confidence && (
              <Badge variant="outline" className="text-muted-foreground">
                confidence: {dossier.confidence}
              </Badge>
            )}
            {dossier.knowledgeTags && dossier.knowledgeTags.length > 0 && (
              <div className="flex flex-wrap gap-1">
                {dossier.knowledgeTags.map((t, i) => (
                  <span
                    key={i}
                    className="rounded bg-muted px-2 py-0.5 text-xs text-muted-foreground"
                  >
                    {t}
                  </span>
                ))}
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    </section>
  );
}
