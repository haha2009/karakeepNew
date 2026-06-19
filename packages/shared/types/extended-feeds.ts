import { z } from "zod";
import { zFeedSchema } from "./feeds";

const MAX_FEED_URL_LENGTH = 2000;
const MAX_FEED_NAME_LENGTH = 100;

export enum Platform {
  LINUXDO = "linuxdo",
  X = "x",
  TWITTER = "twitter",
  REDDIT = "reddit",
}

export const zPlatformEnumSchema = z.enum([
  Platform.LINUXDO,
  Platform.X,
  Platform.TWITTER,
  Platform.REDDIT,
]);

// Platform type is provided by the enum above

export const zExtendedFeedsSchema = z.object({
  id: z.string(),
  name: z.string().min(1).max(MAX_FEED_NAME_LENGTH),
  url: z.string().url(),
  enabled: z.boolean(),
  importTags: z.boolean(),
  lastFetchedStatus: z.enum(["success", "failure", "pending"]).nullable(),
  lastFetchedAt: z.date().nullable(),
  lastSuccessfulFetchAt: z.date().nullable(),
  platform: zPlatformEnumSchema.optional(),
  githubRepo: z
    .object({
      owner: z.string(),
      name: z.string(),
    })
    .optional(),
});

export type ZFeed = z.infer<typeof zFeedSchema>;

export const zNewFeedSchema = z.object({
  name: z.string().min(1).max(MAX_FEED_NAME_LENGTH),
  url: z.string().max(MAX_FEED_URL_LENGTH).url(),
  enabled: z.boolean(),
  importTags: z.boolean().optional().default(false),
  platform: zPlatformEnumSchema.optional(),
  githubRepo: z
    .object({
      owner: z.string(),
      name: z.string(),
    })
    .optional(),
});

export const zUpdateFeedSchema = z.object({
  feedId: z.string(),
  name: z.string().min(1).max(MAX_FEED_NAME_LENGTH).optional(),
  url: z.string().max(MAX_FEED_URL_LENGTH).url().optional(),
  enabled: z.boolean().optional(),
  importTags: z.boolean().optional(),
  platform: zPlatformEnumSchema.optional(),
  githubRepo: z
    .object({
      owner: z.string(),
      name: z.string(),
    })
    .optional(),
});
