import { and, desc, eq } from "drizzle-orm";

import { ai_providers, providerConfig } from "@karakeep/db/schema";
import { InferenceClientFactory } from "@karakeep/shared/inference";
import serverConfig from "@karakeep/shared/config";
import logger from "@karakeep/shared/logger";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type DB = any;

export interface ActiveProviderRecord {
  id: string;
  name: string;
  apiKey: string;
  baseUrl: string;
  textModel: string;
  imageModel?: string;
  proxyUrl?: string;
  outputSchema: "json" | "structured" | "plain";
  isDefault: boolean;
  isActive: boolean;
}

function maskKey(key: string): string {
  if (!key || key.length <= 12) return key;
  return key.slice(0, 8) + "..." + key.slice(-4);
}

export async function listProviders(
  db: DB,
): Promise<(ActiveProviderRecord & { apiKeyDisplay: string | null })[]> {
  const rows = await db.query.ai_providers.findMany({
    orderBy: [desc(ai_providers.isDefault), desc(ai_providers.createdAt)],
  });
  return rows.map((r: ActiveProviderRecord) => ({
    ...r,
    apiKeyDisplay: r.apiKey ? maskKey(r.apiKey) : null,
  }));
}

export async function resolveActiveProvider(
  db: DB,
): Promise<Omit<ActiveProviderRecord, "apiKey"> & { apiKey: string | null } | null> {
  const candidate = await db.query.ai_providers.findFirst({
    where: and(eq(ai_providers.isActive, true)),
    orderBy: [desc(ai_providers.isDefault)],
  });

  if (candidate) {
    return { ...candidate, apiKey: candidate.apiKey ?? null };
  }

  const legacy = await db.query.providerConfig.findFirst();
  if (legacy) {
    logger.info("[ai-providers] using legacy providerConfig as fallback");
    return {
      id: legacy.id,
      name: "默认 (legacy)",
      apiKey: legacy.apiKey ?? null,
      baseUrl: legacy.baseUrl ?? "",
      textModel: legacy.textModel ?? "deepseek-chat",
      imageModel: legacy.imageModel,
      proxyUrl: undefined,
      outputSchema: (legacy.outputSchema ?? "json") as "json" | "structured" | "plain",
      isDefault: true,
      isActive: true,
    };
  }

  // 3. Fallback: env vars only (pre-DB migration scenario)
  logger.info("[ai-providers] no DB config found, falling back to env vars");
  if (!serverConfig.inference.openAIApiKey) {
    return null;
  }

  return {
    id: "__env__",
    name: "环境变量",
    apiKey: serverConfig.inference.openAIApiKey,
    baseUrl: serverConfig.inference.openAIBaseUrl ?? "",
    textModel: serverConfig.inference.textModel,
    imageModel: serverConfig.inference.imageModel,
    proxyUrl: serverConfig.inference.openAIProxyUrl,
    outputSchema: serverConfig.inference.outputSchema as "json" | "structured" | "plain",
    isDefault: true,
    isActive: true,
  };
}

export async function buildInferenceClient(db: DB) {
  const active = await resolveActiveProvider(db);
  if (!active?.apiKey) return null;

  return InferenceClientFactory.build({
    apiKey: active.apiKey,
    baseURL: active.baseUrl || undefined,
    textModel: active.textModel,
    imageModel: active.imageModel,
    proxyUrl: active.proxyUrl,
    outputSchema: active.outputSchema,
  });
}

export async function setDefaultProvider(db: DB, id: string): Promise<void> {
  const all = (await db.query.ai_providers.findMany()) as ActiveProviderRecord[];
  await Promise.all(
    all.map((r) =>
      db
        .update(ai_providers)
        .set({ isDefault: r.id === id, updatedAt: new Date() })
        .where(eq(ai_providers.id, r.id)),
    ),
  );
}

export async function ensureSingleDefault(db: DB, providerId: string): Promise<void> {
  await setDefaultProvider(db, providerId);
}
