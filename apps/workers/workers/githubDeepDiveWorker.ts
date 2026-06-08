import { eq } from "drizzle-orm";
import { workerStatsCounter } from "metrics";
import { withWorkerEventLog, withWorkerTracing } from "workerTracing";

import type { ZGitHubDeepDiveRequest } from "@karakeep/shared-server";
import { db } from "@karakeep/db";
import { githubProjects } from "@karakeep/db/schema";
import {
  addLogFields,
  fetchGitHubReadme,
  GitHubDeepDiveQueue,
  zGitHubDeepDiveSchema,
} from "@karakeep/shared-server";
import type { AgentDossier } from "@karakeep/shared/types/bookmarks";
import serverConfig from "@karakeep/shared/config";
import { InferenceClientFactory } from "@karakeep/shared/inference";
import logger from "@karakeep/shared/logger";
import { DequeuedJob, getQueueClient } from "@karakeep/shared/queueing";

export class GitHubDeepDiveWorker {
  static async build() {
    logger.info("Starting github deep dive worker ...");
    const worker =
      (await getQueueClient())!.createRunner<ZGitHubDeepDiveRequest>(
        GitHubDeepDiveQueue,
        {
          run: withWorkerTracing(
            "githubDeepDiveWorker.run",
            withWorkerEventLog("githubDeepDiveWorker.run", runDeepDive),
          ),
          onComplete: () => {
            workerStatsCounter.labels("githubDeepDive", "completed").inc();
            return Promise.resolve();
          },
          onError: (job) => {
            workerStatsCounter.labels("githubDeepDive", "failed").inc();
            if (job.numRetriesLeft == 0) {
              workerStatsCounter
                .labels("githubDeepDive", "failed_permanent")
                .inc();
            }
            logger.error(
              `[githubDeepDive] job failed: ${job.error}\n${job.error.stack}`,
            );
            return Promise.resolve();
          },
        },
        {
          concurrency: serverConfig.inference.numWorkers,
          pollIntervalMs: 1000,
          timeoutSecs: 120,
        },
      );

    return worker;
  }
}

async function runDeepDive(job: DequeuedJob<ZGitHubDeepDiveRequest>) {
  const jobId = job.id;

  const request = zGitHubDeepDiveSchema.safeParse(job.data);
  if (!request.success) {
    throw new Error(
      `[githubDeepDive][${jobId}] Got malformed job request: ${request.error.toString()}`,
    );
  }

  const { bookmarkId } = request.data;
  addLogFields<"githubDeepDiveWorker.run">({ "bookmark.id": bookmarkId });

  const gh = await db.query.githubProjects.findFirst({
    where: eq(githubProjects.bookmarkId, bookmarkId),
  });

  if (!gh) {
    logger.warn(
      `[githubDeepDive][${jobId}] githubProjects record not found for bookmark ${bookmarkId}, skipping`,
    );
    return;
  }

  await db
    .update(githubProjects)
    .set({ aiStatus: "pending" })
    .where(eq(githubProjects.bookmarkId, bookmarkId));

  const readme = await fetchGitHubReadme(gh.owner, gh.name);
  const readmeContent = readme
    ? preprocessReadme(readme)
    : "(README not available)";

  const dbProviderConfig = await db.query.providerConfig.findFirst();
  const inferenceClient = InferenceClientFactory.build({
    apiKey: dbProviderConfig?.apiKey ?? undefined,
    baseURL: dbProviderConfig?.baseUrl ?? undefined,
    textModel: dbProviderConfig?.textModel ?? undefined,
    imageModel: dbProviderConfig?.imageModel ?? undefined,
    outputSchema: dbProviderConfig?.outputSchema as
      | "structured"
      | "json"
      | "plain"
      | undefined,
  });
  if (!inferenceClient) {
    logger.debug(
      `[githubDeepDive][${jobId}] No inference client configured, setting aiStatus to failed`,
    );
    await db
      .update(githubProjects)
      .set({ aiStatus: "failed" })
      .where(eq(githubProjects.bookmarkId, bookmarkId));
    return;
  }

  const prompt = buildPrompt({
    name: gh.name,
    description: gh.description,
    language: gh.language,
    stars: gh.stars,
    topics: gh.topics,
    readmeContent,
  });

  const result = await inferenceClient.inferFromText(prompt, { schema: null });

  let humanSummary: string;
  let dossier: AgentDossier;

  try {
    const parsed = JSON.parse(result.response);
    humanSummary = parsed.humanSummary ?? "";
    dossier = parsed.dossier;
  } catch {
    throw new Error(
      `[githubDeepDive][${jobId}] Failed to parse LLM response as JSON: ${result.response.slice(0, 200)}`,
    );
  }

  if (!dossier || !dossier.oneLiner) {
    throw new Error(
      `[githubDeepDive][${jobId}] LLM response missing required dossier fields`,
    );
  }

  await db
    .update(githubProjects)
    .set({
      humanSummary: humanSummary || undefined,
      agentDossier: dossier,
      aiStatus: "completed",
    })
    .where(eq(githubProjects.bookmarkId, bookmarkId));

  logger.info(`[githubDeepDive][${jobId}] Completed for ${gh.fullName}`);
}

function preprocessReadme(raw: string): string {
  const lines = raw.split("\n").filter((l) => l.trim());
  const cleaned = lines
    .map((l) => l.replace(/!\[.*?\]\(.*?\)/g, "").trim())
    .filter(Boolean)
    .join("\n");
  return cleaned.length > 8000 ? cleaned.slice(0, 8000) : cleaned;
}

function buildPrompt(meta: {
  name: string;
  description: string | null;
  language: string | null;
  stars: number | null;
  topics: string[] | null;
  readmeContent: string;
}): string {
  return `你是一个技术分析专家。分析以下 GitHub 项目的 README 和元数据，返回纯 JSON。

项目名称：${meta.name}
官方描述：${meta.description ?? "无"}
编程语言：${meta.language ?? "未知"}
Stars：${meta.stars ?? "未知"}
Topics：${meta.topics?.join(", ") ?? "无"}

README 内容：
${meta.readmeContent}

分析要求：
1. 先分析标签（topics）——标签是最可靠的分类线索，不要被项目名称误导
2. 常见标签映射参考：alist/aliyunpan/baidupan/clouddrive/nas → 云盘管理
3. 结合 README 确认核心功能和技术栈
4. 最后判断项目的成熟度和目标用户

请返回以下 JSON（不要任何其他文字，严格 JSON 格式）：
{
  "humanSummary": "30-60字中文通俗简介，让非技术用户也能看懂这个项目是做什么的，不要重复项目名称（卡片标题已经显示了）",
  "dossier": {
    "oneLiner": "一句话精准概括项目定位（20字内）",
    "overview": "200-500字的完整项目介绍，面向 AI Agent 阅读，包含：项目目的、核心功能、架构特点、使用方式",
    "category": "项目分类（如云盘管理、前端框架、CLI工具、DevOps、数据库等）",
    "keyFeatures": ["核心功能点列表，每点10字以内"],
    "techStack": ["技术栈列表，如Go", "Vue.js", "PostgreSQL"],
    "useCases": ["适用场景列表"],
    "alternatives": ["替代品或竞品列表，项目名即可"],
    "knowledgeTags": ["5-10个用于搜索的标签"],
    "maturity": "active 或 stable 或 inactive",
    "confidence": "high 或 medium 或 low"
  }
}`;
}
