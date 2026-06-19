import { eq } from "drizzle-orm";
import { workerStatsCounter } from "metrics";
import { withWorkerEventLog, withWorkerTracing } from "workerTracing";

import type { ZGitHubDeepDiveRequest } from "@karakeep/shared-server";
import { db } from "@karakeep/db";
import { githubProjects } from "@karakeep/db/schema";
import {
  addLogFields,
  GitHubDeepDiveQueue,
  runGitHubDeepDive,
  zGitHubDeepDiveSchema,
} from "@karakeep/shared-server";
import serverConfig from "@karakeep/shared/config";
import logger from "@karakeep/shared/logger";
import { DequeuedJob, getQueueClient } from "@karakeep/shared/queueing";

/**
 * Thin worker wrapper around the canonical `runGitHubDeepDive` pipeline
 * (rules + a single AI call) defined in shared-server.
 *
 * All GitHub deep-dive work — whether triggered by bookmark creation, the
 * crawler, or a manual tRPC action — funnels through this queue so LLM calls
 * never run inline in an HTTP request.
 */
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
          onError: async (job) => {
            workerStatsCounter.labels("githubDeepDive", "failed").inc();
            if (job.numRetriesLeft == 0) {
              workerStatsCounter
                .labels("githubDeepDive", "failed_permanent")
                .inc();
              // Mark the project as failed so the UI doesn't show it as
              // permanently "pending" after retries are exhausted.
              await tryMarkFailed(job.data?.bookmarkId);
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
          timeoutSecs: serverConfig.inference.jobTimeoutSec,
        },
      );

    return worker;
  }
}

async function tryMarkFailed(bookmarkId: string | undefined) {
  if (!bookmarkId) return;
  try {
    await db
      .update(githubProjects)
      .set({ aiStatus: "failed" })
      .where(eq(githubProjects.bookmarkId, bookmarkId));
  } catch (e) {
    logger.warn(`[githubDeepDive] failed to mark project as failed: ${e}`);
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

  const result = await runGitHubDeepDive({ bookmarkId, db });
  if (!result.success) {
    throw new Error(
      `[githubDeepDive][${jobId}] ${result.error ?? "deep dive failed"}`,
    );
  }
}
