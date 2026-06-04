import { and, eq } from "drizzle-orm";
import { z } from "zod";

import type { ZOpenAIRequest } from "@karakeep/shared-server";
import type { InferenceClient } from "@karakeep/shared/inference";
import { db } from "@karakeep/db";
import {
  bookmarks,
  bookmarkLists,
  bookmarksInLists,
  customPrompts,
  users,
} from "@karakeep/db/schema";
import {
  addLogFields,
  setSpanAttributes,
  triggerSearchReindex,
} from "@karakeep/shared-server";
import serverConfig from "@karakeep/shared/config";
import logger from "@karakeep/shared/logger";

import { DequeuedJob, EnqueueOptions } from "@karakeep/shared/queueing";
import { BookmarkTypes } from "@karakeep/shared/types/bookmarks";
import { RuleEngine } from "@karakeep/trpc/lib/ruleEngine";
import { Bookmark } from "@karakeep/trpc/models/bookmarks";
import { WebhooksService } from "@karakeep/trpc/models/webhooks.service";

import { connectTags } from "./tagging";

const openAIResponseSchema = z.object({
  summary: z.string(),
  tags: z.array(z.string()),
  targetFolder: z.string().nullable(),
});

function parseJsonFromLLMResponse(response: string): unknown {
  const trimmedResponse = response.trim();

  try {
    return JSON.parse(trimmedResponse);
  } catch {
    const jsonBlockRegex = /```(?:json)?\s*(\{[\s\S]*?\})\s*```/i;
    const match = trimmedResponse.match(jsonBlockRegex);

    if (match) {
      try {
        return JSON.parse(match[1]);
      } catch {
        throw new Error(`Failed to parse JSON from markdown block`);
      }
    }

    throw new Error(`Failed to parse JSON from LLM response`);
  }
}

interface FolderNode {
  id: string;
  name: string;
  parentId: string | null;
  children: FolderNode[];
}

function buildFolderTree(
  lists: {
    id: string;
    name: string;
    parentId: string | null;
  }[],
): FolderNode[] {
  const map = new Map<string, FolderNode>();
  const roots: FolderNode[] = [];

  for (const list of lists) {
    map.set(list.id, { ...list, children: [] });
  }

  for (const node of map.values()) {
    if (node.parentId && map.has(node.parentId)) {
      map.get(node.parentId)!.children.push(node);
    } else {
      roots.push(node);
    }
  }

  return roots;
}

function formatFolderTree(nodes: FolderNode[], prefix = ""): string {
  const lines: string[] = [];
  for (const node of nodes) {
    const path = prefix ? `${prefix}/${node.name}` : node.name;
    lines.push(`- ${path}`);
    if (node.children.length > 0) {
      lines.push(formatFolderTree(node.children, path));
    }
  }
  return lines.join("\n");
}

function collectFolderPaths(
  nodes: FolderNode[],
  prefix = "",
): Map<string, string> {
  const paths = new Map<string, string>();
  for (const node of nodes) {
    const fullPath = prefix ? `${prefix}/${node.name}` : node.name;
    paths.set(fullPath, node.id);
    for (const [childPath, childId] of collectFolderPaths(
      node.children,
      fullPath,
    )) {
      paths.set(childPath, childId);
    }
  }
  return paths;
}

async function fetchBookmarkDetails(bookmarkId: string) {
  const bookmark = await db.query.bookmarks.findFirst({
    where: eq(bookmarks.id, bookmarkId),
    columns: { id: true, userId: true, type: true },
    with: {
      link: {
        columns: {
          title: true,
          description: true,
          url: true,
          publisher: true,
          author: true,
          contentAssetId: true,
          htmlContent: true,
        },
      },
      text: {
        columns: {
          text: true,
        },
      },
    },
  });
  return bookmark;
}

export async function runClassify(
  bookmarkId: string,
  job: DequeuedJob<ZOpenAIRequest>,
  inferenceClient: InferenceClient,
) {
  const jobId = job.id;

  if (
    !serverConfig.inference.enableAutoTagging &&
    !serverConfig.inference.enableAutoSummarization
  ) {
    logger.debug(
      `[inference][${jobId}] Skipping classify job for bookmark with id "${bookmarkId}" because both tagging and summarization are disabled.`,
    );
    return;
  }

  const bookmarkData = await fetchBookmarkDetails(bookmarkId);
  if (!bookmarkData) {
    throw new Error(
      `[inference][${jobId}] bookmark with id ${bookmarkId} was not found`,
    );
  }

  setSpanAttributes({
    "user.id": bookmarkData.userId,
    "bookmark.id": bookmarkData.id,
    "inference.type": "classify",
  });
  addLogFields<"inferenceWorker.run">({
    "user.id": bookmarkData.userId,
    "bookmark.url": bookmarkData.link?.url,
    "bookmark.content_type": bookmarkData.type,
    "inference.model": serverConfig.inference.textModel,
  });

  const userSettings = await db.query.users.findFirst({
    where: eq(users.id, bookmarkData.userId),
    columns: {
      autoTaggingEnabled: true,
      autoSummarizationEnabled: true,
      inferredTagLang: true,
    },
  });

  if (
    userSettings?.autoTaggingEnabled === false &&
    userSettings?.autoSummarizationEnabled === false
  ) {
    logger.debug(
      `[inference][${jobId}] Skipping classify for bookmark "${bookmarkId}" because user disabled both tagging and summarization.`,
    );
    return;
  }

  if (bookmarkData.type === BookmarkTypes.ASSET) {
    logger.debug(
      `[inference][${jobId}] Skipping classify for asset bookmark "${bookmarkId}". Asset bookmarks use their own pipeline.`,
    );
    return;
  }

  if (!bookmarkData.link && !bookmarkData.text) {
    logger.info(
      `[inference][${jobId}] No content found for bookmark "${bookmarkId}". Skipping classify.`,
    );
    return;
  }

  const link = bookmarkData.link;
  let textContent = "";
  if (bookmarkData.type === BookmarkTypes.LINK && link) {
    const content =
      (await Bookmark.getBookmarkPlainTextContent(
        {
          contentAssetId: link.contentAssetId,
          htmlContent: link.htmlContent,
        },
        bookmarkData.userId,
      )) ?? "";
    textContent = `
URL: ${link.url ?? ""}
Title: ${link.title ?? ""}
Description: ${link.description ?? ""}
Content: ${content}
Publisher: ${link.publisher ?? ""}
Author: ${link.author ?? ""}
`;
  } else if (bookmarkData.text) {
    textContent = bookmarkData.text.text ?? "";
  }

  if (!textContent.trim()) {
    logger.info(
      `[inference][${jobId}] No content to classify for bookmark "${bookmarkId}".`,
    );
    return;
  }

  const allLists = await db.query.bookmarkLists.findMany({
    where: and(
      eq(bookmarkLists.userId, bookmarkData.userId),
      eq(bookmarkLists.type, "manual"),
    ),
    columns: {
      id: true,
      name: true,
      parentId: true,
    },
  });

  const folderTree = buildFolderTree(allLists);
  const folderPaths = collectFolderPaths(folderTree);
  const folderTreeText = formatFolderTree(folderTree);

  const lang =
    userSettings?.inferredTagLang ?? serverConfig.inference.inferredTagLang;

  const customPromptList = await db.query.customPrompts.findMany({
    where: and(
      eq(customPrompts.userId, bookmarkData.userId),
      eq(customPrompts.appliesTo, "all_tagging"),
    ),
    columns: { text: true },
  });

  const systemPrompt = `You are an expert assistant that analyzes bookmarked content and returns structured information.

User's folder structure:
${folderTreeText || "(no folders yet)"}

Analyze the bookmark content and return a JSON object with:
{
  "summary": "A concise one-sentence summary of what this is (in ${lang}). Max 150 characters.",
  "tags": ["tag1", "tag2", "tag3"],
  "targetFolder": "full/path/to/folder" | null
}

Rules:
- Summary: Must be in ${lang}, concise, straight to the point.
- Tags: 3-5 tags in English lowercase. Use hyphens for multi-word tags. Reflect language, purpose, domain, topic.
- targetFolder: Choose the MOST specific folder from the user's structure above. Use full path separated by "/". Return null if none fits.
- If the content is an error page, login wall, or boilerplate, return null for targetFolder and empty tags.`;

  const contentPrompt = `<BOOKMARK_CONTENT>
${textContent}
</BOOKMARK_CONTENT>

${customPromptList.length > 0 ? `Additional user instructions:\n${customPromptList.map((p) => `- ${p.text}`).join("\n")}` : ""}

Return ONLY valid JSON.`;

  addLogFields<"inferenceWorker.run">({
    "inference.prompt.size": Buffer.byteLength(
      systemPrompt + contentPrompt,
      "utf8",
    ),
  });

  const fullPrompt = `${systemPrompt}\n\n${contentPrompt}`;

  const inferenceResult = await inferenceClient.inferFromText(fullPrompt, {
    schema: openAIResponseSchema,
    abortSignal: job.abortSignal,
  });

  if (!inferenceResult.response) {
    throw new Error(
      `[inference][${jobId}] Failed to classify bookmark ${bookmarkId}, empty response.`,
    );
  }

  let parsed: z.infer<typeof openAIResponseSchema>;
  try {
    parsed = openAIResponseSchema.parse(
      parseJsonFromLLMResponse(inferenceResult.response),
    );
  } catch (e) {
    throw new Error(
      `[inference][${jobId}] Failed to parse classify response: ${e}. Raw: ${inferenceResult.response.substring(0, 100)}`,
    );
  }

  addLogFields<"inferenceWorker.run">({
    "inference.total_tokens": inferenceResult.totalTokens,
    "inference.tagging.num_generated_tags": parsed.tags.length,
  });

  logger.info(
    `[inference][${jobId}] Classified bookmark "${bookmarkId}" using ${inferenceResult.totalTokens} tokens. Summary: "${parsed.summary.substring(0, 60)}...", Tags: ${parsed.tags.join(", ")}, Folder: ${parsed.targetFolder ?? "none"}`,
  );

  if (parsed.summary && userSettings?.autoSummarizationEnabled !== false) {
    await db
      .update(bookmarks)
      .set({
        summary: parsed.summary,
        modifiedAt: new Date(),
      })
      .where(eq(bookmarks.id, bookmarkId));
  }

  if (parsed.tags.length > 0 && userSettings?.autoTaggingEnabled !== false) {
    const cleanedTags = parsed.tags
      .map((t) => {
        let tag = t;
        if (tag.startsWith("#")) tag = tag.slice(1);
        return tag.trim();
      })
      .filter(Boolean);
    await connectTags(bookmarkId, cleanedTags, bookmarkData.userId);
  }

  if (parsed.targetFolder) {
    const pathParts = parsed.targetFolder.split("/").filter(Boolean);
    const targetPath = pathParts.join("/");

    const targetListId = folderPaths.get(targetPath);

    if (targetListId) {
      await db
        .insert(bookmarksInLists)
        .values({
          listId: targetListId,
          bookmarkId,
        })
        .onConflictDoNothing();

      await RuleEngine.triggerOnEvent(
        bookmarkData.userId,
        bookmarkId,
        [{ type: "addedToList", listId: targetListId }],
        undefined,
        db,
      );

      logger.info(
        `[inference][${jobId}] Added bookmark "${bookmarkId}" to folder "${targetPath}"`,
      );
    } else {
      logger.warn(
        `[inference][${jobId}] AI suggested folder "${targetPath}" but no match found in user's lists`,
      );
    }
  }

  const enqueueOpts: EnqueueOptions = {
    priority: job.priority,
    groupId: bookmarkData.userId,
  };

  {
    const webhookService = new WebhooksService(db);
    await webhookService.triggerWebhook(
      bookmarkId,
      "ai tagged",
      bookmarkData.userId,
      enqueueOpts,
    );
  }

  await triggerSearchReindex(bookmarkId, enqueueOpts);
}
