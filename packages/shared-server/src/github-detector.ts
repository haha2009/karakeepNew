import { eq } from "drizzle-orm";

import {
  bookmarks,
  bookmarkLinks,
  githubProjects,
} from "@karakeep/db/schema";
import { GitHubDeepDiveQueue } from "./queues";
import { extractGitHubRepo } from "./github";
import logger from "@karakeep/shared/logger";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type DB = any;

export async function onBookmarkCreated(bookmarkId: string, db: DB) {
  try {
    const link = await db.query.bookmarkLinks.findFirst({
      where: eq(bookmarkLinks.id, bookmarkId),
      columns: { url: true },
    });

    if (!link?.url) return;

    const repo = extractGitHubRepo(link.url);
    if (!repo) return;

    const existing = await db.query.githubProjects.findFirst({
      where: eq(githubProjects.bookmarkId, bookmarkId),
      columns: { id: true },
    });
    if (existing) return;

    const bookmark = await db.query.bookmarks.findFirst({
      where: eq(bookmarks.id, bookmarkId),
      columns: { userId: true },
    });
    if (!bookmark) return;

    await db.insert(githubProjects).values({
      userId: bookmark.userId,
      bookmarkId,
      fullName: repo.fullName,
      url: `https://github.com/${repo.owner}/${repo.name}`,
      name: repo.name,
      owner: repo.owner,
      description: null,
      aiStatus: "pending",
      valueScore: "unscored",
      tags: [],
      agentTags: [],
    });

    await GitHubDeepDiveQueue.enqueue(
      { bookmarkId },
      { priority: 5 },
    ).catch((e: unknown) => {
      console.error(`[github-detector] enqueue failed: ${e}`);
    });

    logger.info(
      `[github-detector] auto-created project for ${repo.fullName}`,
    );
  } catch (e) {
    logger.warn(`[github-detector] failed for bookmark ${bookmarkId}: ${e instanceof Error ? e.message : e}`);
  }
}
