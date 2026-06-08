import { and, asc, desc, eq, gte, ilike, or, sql } from "drizzle-orm";
import { z } from "zod";

import { bookmarkLinks } from "@karakeep/db/schema";
import { githubProjects } from "@karakeep/db/schema";
import {
  fetchGitHubRepoMetadata,
  extractGitHubRepo,
} from "@karakeep/shared-server";
import { zGitHubProjectSchema } from "@karakeep/shared/types/bookmarks";

import { createScopedAuthedProcedure, router } from "../index";

const githubProcedure = createScopedAuthedProcedure("bookmarks");

const zGitHubProjectFullSchema = zGitHubProjectSchema.extend({
  id: z.string(),
  userId: z.string(),
  bookmarkId: z.string().nullable(),
  lastFetchedAt: z.date().nullable(),
  createdAt: z.date(),
  modifiedAt: z.date().nullable(),
});

function mapProject(p: typeof githubProjects.$inferSelect) {
  return {
    id: p.id,
    userId: p.userId,
    bookmarkId: p.bookmarkId,
    fullName: p.fullName,
    url: p.url,
    name: p.name,
    owner: p.owner,
    description: p.description,
    stars: p.stars,
    language: p.language,
    topics: p.topics,
    homepage: p.homepage,
    license: p.license,
    humanSummary: p.humanSummary,
    agentDossier: p.agentDossier,
    tags: p.tags,
    pushedAt: p.pushedAt,
    lastFetchedAt: p.lastFetchedAt,
    createdAt: p.createdAt,
    modifiedAt: p.modifiedAt,
  };
}

export const githubAppRouter = router({
  search: githubProcedure
    .input(
      z.object({
        query: z.string().optional(),
        language: z.string().optional(),
        tag: z.string().optional(),
        minStars: z.number().optional(),
        limit: z.number().max(100).optional().default(20),
        sortOrder: z.enum(["asc", "desc"]).optional().default("desc"),
      }),
    )
    .output(
      z.object({
        projects: z.array(zGitHubProjectFullSchema),
      }),
    )
    .query(async ({ ctx, input }) => {
      const conditions = [eq(githubProjects.userId, ctx.user.id)];

      if (input.query) {
        conditions.push(
          or(
            ilike(githubProjects.fullName, `%${input.query}%`),
            ilike(githubProjects.description ?? sql`''`, `%${input.query}%`),
            ilike(githubProjects.humanSummary ?? sql`''`, `%${input.query}%`),
          )!,
        );
      }

      if (input.language) {
        conditions.push(eq(githubProjects.language, input.language));
      }

      if (input.tag) {
        conditions.push(
          sql`EXISTS (SELECT 1 FROM json_each(${githubProjects.tags}) WHERE value = ${input.tag})`,
        );
      }

      if (input.minStars !== undefined) {
        conditions.push(gte(githubProjects.stars!, input.minStars));
      }

      const projects = await ctx.db.query.githubProjects.findMany({
        where: and(...conditions),
        limit: input.limit,
        orderBy:
          input.sortOrder === "desc"
            ? desc(githubProjects.stars)
            : asc(githubProjects.stars),
      });

      return { projects: projects.map(mapProject) };
    }),

  get: githubProcedure
    .input(z.object({ fullName: z.string() }))
    .output(zGitHubProjectFullSchema.nullable())
    .query(async ({ ctx, input }) => {
      const project = await ctx.db.query.githubProjects.findFirst({
        where: and(
          eq(githubProjects.fullName, input.fullName),
          eq(githubProjects.userId, ctx.user.id),
        ),
      });
      return project ? mapProject(project) : null;
    }),

  refreshBookmark: githubProcedure
    .input(z.object({ bookmarkId: z.string() }))
    .output(zGitHubProjectFullSchema.nullable())
    .mutation(async ({ ctx, input }) => {
      const link = await ctx.db.query.bookmarkLinks.findFirst({
        where: eq(bookmarkLinks.id, input.bookmarkId),
        columns: { url: true },
      });
      if (!link) return null;

      const repo = extractGitHubRepo(link.url);
      if (!repo) return null;

      const existing = await ctx.db.query.githubProjects.findFirst({
        where: eq(githubProjects.bookmarkId, input.bookmarkId),
      });

      const meta = await fetchGitHubRepoMetadata(repo.owner, repo.name);
      if (!meta) return null;

      const now = new Date();

      if (existing) {
        await ctx.db
          .update(githubProjects)
          .set({
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
            lastFetchedAt: now,
          })
          .where(eq(githubProjects.id, existing.id));
      } else {
        await ctx.db.insert(githubProjects).values({
          userId: ctx.user.id,
          bookmarkId: input.bookmarkId,
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
          lastFetchedAt: now,
        });
      }

      await ctx.db
        .update(bookmarkLinks)
        .set({
          title: meta.description ?? meta.name,
          description: meta.description,
        })
        .where(eq(bookmarkLinks.id, input.bookmarkId));

      const project = await ctx.db.query.githubProjects.findFirst({
        where: eq(githubProjects.bookmarkId, input.bookmarkId),
      });
      return project ? mapProject(project) : null;
    }),

  profile: githubProcedure
    .output(
      z.object({
        totalProjects: z.number(),
        languages: z.array(
          z.object({ language: z.string(), count: z.number() }),
        ),
        topTags: z.array(z.object({ tag: z.string(), count: z.number() })),
        totalStars: z.number(),
        avgStars: z.number(),
      }),
    )
    .query(async ({ ctx }) => {
      const projects = await ctx.db.query.githubProjects.findMany({
        where: eq(githubProjects.userId, ctx.user.id),
        columns: {
          stars: true,
          language: true,
          tags: true,
        },
      });

      const langMap = new Map<string, number>();
      const tagMap = new Map<string, number>();
      let totalStars = 0;

      for (const p of projects) {
        if (p.language) {
          langMap.set(p.language, (langMap.get(p.language) ?? 0) + 1);
        }
        if (p.tags) {
          for (const tag of p.tags) {
            tagMap.set(tag, (tagMap.get(tag) ?? 0) + 1);
          }
        }
        totalStars += p.stars ?? 0;
      }

      return {
        totalProjects: projects.length,
        languages: [...langMap.entries()]
          .map(([language, count]) => ({ language, count }))
          .sort((a, b) => b.count - a.count),
        topTags: [...tagMap.entries()]
          .map(([tag, count]) => ({ tag, count }))
          .sort((a, b) => b.count - a.count)
          .slice(0, 20),
        totalStars,
        avgStars:
          projects.length > 0 ? Math.round(totalStars / projects.length) : 0,
      };
    }),

  recommend: githubProcedure
    .input(
      z.object({
        description: z.string(),
        limit: z.number().max(20).optional().default(5),
      }),
    )
    .output(
      z.object({
        projects: z.array(zGitHubProjectFullSchema),
        matchReason: z.string(),
      }),
    )
    .query(async ({ ctx, input }) => {
      const keywords = input.description
        .toLowerCase()
        .split(/[\s,;]+/)
        .filter((k) => k.length > 2);

      const projects = await ctx.db.query.githubProjects.findMany({
        where: eq(githubProjects.userId, ctx.user.id),
        columns: {
          id: true,
          fullName: true,
          description: true,
          humanSummary: true,
          tags: true,
          language: true,
          stars: true,
          topics: true,
          url: true,
          name: true,
          owner: true,
          homepage: true,
          license: true,
          agentDossier: true,
          pushedAt: true,
          lastFetchedAt: true,
          bookmarkId: true,
          userId: true,
          createdAt: true,
          modifiedAt: true,
        },
      });

      type Scored = (typeof projects)[number] & { score: number };

      const scored: Scored[] = projects
        .map((p) => {
          let score = 0;
          const text = [
            p.fullName,
            p.description ?? "",
            p.humanSummary ?? "",
            ...(p.tags ?? []),
            ...(p.topics ?? []),
            p.language ?? "",
          ]
            .join(" ")
            .toLowerCase();

          for (const keyword of keywords) {
            if (text.includes(keyword)) {
              score += 1;
            }
          }

          if (p.stars) {
            score += Math.log2(p.stars + 1) * 0.5;
          }

          return { ...p, score };
        })
        .filter((p) => p.score > 0)
        .sort((a, b) => b.score - a.score)
        .slice(0, input.limit);

      return {
        projects: scored.map(mapProject),
        matchReason: `匹配了 ${scored.length} 个项目（基于 ${keywords.length} 个关键词）`,
      };
    }),
});
