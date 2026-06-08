import { and, eq } from "drizzle-orm";

import { db } from "@karakeep/db";
import {
  bookmarkLinks,
  bookmarks,
  bookmarkLists,
  bookmarksInLists,
  githubProjects,
} from "@karakeep/db/schema";
import { LinkCrawlerQueue, OpenAIQueue } from "@karakeep/shared-server";
import {
  extractGitHubRepo,
  fetchGitHubRepoMetadata,
} from "@karakeep/shared-server";
import { BookmarkTypes } from "@karakeep/shared/types/bookmarks";
import logger from "@karakeep/shared/logger";

const GITHUB_URL_RE = /https?:\/\/(?:www\.)?github\.com\/[\w.-]+\/[\w.-]+/g;

function extractAllRepos(text: string): string[] {
  const matches = text.match(GITHUB_URL_RE);
  if (!matches) return [];
  const seen = new Set<string>();
  const unique: string[] = [];
  for (const url of matches) {
    const repo = extractGitHubRepo(url);
    if (repo && !seen.has(repo.fullName)) {
      seen.add(repo.fullName);
      unique.push(url);
    }
  }
  return unique;
}

export async function autoCreateGitHubBookmarks(
  userId: string,
  sourceBookmarkId: string,
  textContent: string,
): Promise<void> {
  const repoUrls = extractAllRepos(textContent);
  if (repoUrls.length === 0) return;

  const sourceLink = await db.query.bookmarkLinks.findFirst({
    where: eq(bookmarkLinks.id, sourceBookmarkId),
    columns: { url: true },
  });
  const sourceUrl = sourceLink?.url;

  for (const repoUrl of repoUrls) {
    const repo = extractGitHubRepo(repoUrl);
    if (!repo) continue;

    if (sourceUrl === repoUrl) {
      await attachGitHubProject(
        userId,
        sourceBookmarkId,
        repo.owner,
        repo.name,
        repo.fullName,
      );
      continue;
    }

    const existingProject = await db.query.githubProjects.findFirst({
      where: eq(githubProjects.fullName, repo.fullName),
      columns: { id: true },
    });
    if (existingProject) {
      logger.info(`[github] Skipping ${repo.fullName} — already tracked`);
      continue;
    }

    const existingLink = await db.query.bookmarkLinks.findFirst({
      where: eq(bookmarkLinks.url, repoUrl),
      columns: { id: true },
    });
    if (existingLink) {
      logger.info(`[github] Skipping ${repo.fullName} — bookmark exists`);
      continue;
    }

    logger.info(`[github] Creating bookmark for ${repo.fullName}`);
    const meta = await fetchGitHubRepoMetadata(repo.owner, repo.name);
    if (!meta) {
      logger.warn(`[github] No API data for ${repo.fullName}, skipping`);
      continue;
    }

    const bookmark = (
      await db
        .insert(bookmarks)
        .values({
          userId,
          title: repo.fullName,
          type: BookmarkTypes.LINK,
          summarizationStatus: "pending",
        })
        .returning()
    )[0];

    await db.insert(bookmarkLinks).values({
      id: bookmark.id,
      url: meta.url,
      title: meta.description ?? meta.name,
      description: meta.description,
      imageUrl: meta.ownerAvatarUrl,
    });

    await db.insert(githubProjects).values({
      userId,
      bookmarkId: bookmark.id,
      fullName: meta.fullName,
      url: meta.url,
      name: meta.name,
      owner: meta.owner,
      description: meta.description,
      stars: meta.stars,
      language: meta.language,
      topics: meta.topics,
      homepage: meta.homepage,
      license: meta.license,
      pushedAt: meta.pushedAt ? new Date(meta.pushedAt) : null,
      lastFetchedAt: new Date(),
    });

    const ghFolder = await db.query.bookmarkLists.findFirst({
      where: and(
        eq(bookmarkLists.userId, userId),
        eq(bookmarkLists.name, "GitHub"),
      ),
      columns: { id: true },
    });

    if (ghFolder) {
      await db
        .insert(bookmarksInLists)
        .values({ listId: ghFolder.id, bookmarkId: bookmark.id })
        .onConflictDoNothing();
    }

    await LinkCrawlerQueue.enqueue(
      { bookmarkId: bookmark.id },
      { groupId: userId },
    );

    await OpenAIQueue.enqueue(
      { bookmarkId: bookmark.id, type: "classify" },
      { groupId: userId },
    );

    logger.info(
      `[github] Created bookmark ${bookmark.id} for ${repo.fullName} (${meta.stars}★)`,
    );
  }
}

async function attachGitHubProject(
  userId: string,
  bookmarkId: string,
  owner: string,
  name: string,
  fullName: string,
): Promise<void> {
  const existing = await db.query.githubProjects.findFirst({
    where: eq(githubProjects.bookmarkId, bookmarkId),
    columns: { id: true },
  });
  if (existing) {
    logger.info(`[github] Source ${fullName} already has a project entry`);
    return;
  }

  logger.info(`[github] Attaching project ${fullName} to source bookmark`);
  const meta = await fetchGitHubRepoMetadata(owner, name);
  if (!meta) {
    logger.warn(`[github] No API data for ${fullName}, skipping`);
    return;
  }

  await db.insert(githubProjects).values({
    userId,
    bookmarkId,
    fullName: meta.fullName,
    url: meta.url,
    name: meta.name,
    owner: meta.owner,
    description: meta.description,
    stars: meta.stars,
    language: meta.language,
    topics: meta.topics,
    homepage: meta.homepage,
    license: meta.license,
    pushedAt: meta.pushedAt ? new Date(meta.pushedAt) : null,
    lastFetchedAt: new Date(),
  });

  await db
    .update(bookmarkLinks)
    .set({
      title: meta.description ?? meta.name,
      description: meta.description,
    })
    .where(eq(bookmarkLinks.id, bookmarkId));

  await OpenAIQueue.enqueue(
    { bookmarkId, type: "classify" },
    { groupId: userId },
  );

  logger.info(
    `[github] Attached ${fullName} (${meta.stars}★) to source bookmark ${bookmarkId}`,
  );
}
