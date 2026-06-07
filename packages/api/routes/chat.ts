import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import OpenAI from "openai";
import { z } from "zod";

import serverConfig from "@karakeep/shared/config";

import { authMiddleware } from "../middlewares/auth";

const systemPrompt = `你是 Karakeep 的 AI 助手，熟悉用户的全部收藏。

你可以搜索知识库、获取详情、操作收藏（打标签、归档、收藏、移文件夹、写笔记）。

回答规则：
- 用中文回答，自然友好
- 需要信息时先搜索知识库，不要编造
- 操作前先确认用户意图
- 操作完成后告知结果`;

// ── Route ──────────────────────────────────────────────

const app = new Hono().use(authMiddleware).post(
  "/",
  zValidator(
    "json",
    z.object({
      message: z.string().min(1).max(4000),
    }),
  ),
  async (c) => {
    const { message } = c.req.valid("json");
    const api = c.var.api;
    const db = c.var.ctx.db;

    const providerConfig = await db.query.providerConfig.findFirst();
    const apiKey =
      providerConfig?.apiKey ?? serverConfig.inference.openAIApiKey;
    if (!apiKey) {
      return c.json({ error: "AI provider not configured" }, 400);
    }

    const openai = new OpenAI({
      apiKey,
      baseURL: providerConfig?.baseUrl ?? serverConfig.inference.openAIBaseUrl,
    });

    const textModel =
      providerConfig?.textModel ?? serverConfig.inference.textModel;

    const tools: OpenAI.ChatCompletionTool[] = [
      {
        type: "function",
        function: {
          name: "search_bookmarks",
          description: "搜索收藏的知识库",
          parameters: {
            type: "object",
            properties: {
              query: { type: "string", description: "搜索关键词" },
              limit: { type: "number", description: "返回数量", default: 10 },
            },
            required: ["query"],
          },
        },
      },
      {
        type: "function",
        function: {
          name: "get_bookmark",
          description: "获取收藏的完整详情",
          parameters: {
            type: "object",
            properties: {
              bookmarkId: { type: "string", description: "收藏 ID" },
            },
            required: ["bookmarkId"],
          },
        },
      },
      {
        type: "function",
        function: {
          name: "get_lists",
          description: "获取所有文件夹列表",
          parameters: {
            type: "object",
            properties: {},
            required: [],
          },
        },
      },
      {
        type: "function",
        function: {
          name: "tag_bookmark",
          description: "给收藏打标签",
          parameters: {
            type: "object",
            properties: {
              bookmarkId: { type: "string", description: "收藏 ID" },
              tags: {
                type: "array",
                items: { type: "string" },
                description: "标签名列表",
              },
            },
            required: ["bookmarkId", "tags"],
          },
        },
      },
      {
        type: "function",
        function: {
          name: "archive_bookmark",
          description: "归档或取消归档收藏",
          parameters: {
            type: "object",
            properties: {
              bookmarkId: { type: "string", description: "收藏 ID" },
              archived: {
                type: "boolean",
                description: "true=归档, false=取消归档",
              },
            },
            required: ["bookmarkId", "archived"],
          },
        },
      },
      {
        type: "function",
        function: {
          name: "favorite_bookmark",
          description: "收藏或取消收藏",
          parameters: {
            type: "object",
            properties: {
              bookmarkId: { type: "string", description: "收藏 ID" },
              favourited: {
                type: "boolean",
                description: "true=收藏, false=取消收藏",
              },
            },
            required: ["bookmarkId", "favourited"],
          },
        },
      },
      {
        type: "function",
        function: {
          name: "add_bookmark_to_list",
          description: "把收藏加到文件夹",
          parameters: {
            type: "object",
            properties: {
              bookmarkId: { type: "string", description: "收藏 ID" },
              listId: { type: "string", description: "文件夹 ID" },
            },
            required: ["bookmarkId", "listId"],
          },
        },
      },
      {
        type: "function",
        function: {
          name: "update_note",
          description: "更新收藏笔记",
          parameters: {
            type: "object",
            properties: {
              bookmarkId: { type: "string", description: "收藏 ID" },
              note: { type: "string", description: "笔记内容" },
            },
            required: ["bookmarkId", "note"],
          },
        },
      },
    ] as OpenAI.ChatCompletionTool[];

    const messages: OpenAI.ChatCompletionMessageParam[] = [
      { role: "system", content: systemPrompt },
      { role: "user", content: message },
    ];

    let sources: { id: string; title: string | null; url: string | null }[] =
      [];

    async function executeTool(
      fnName: string,
      rawArgs: string,
    ): Promise<string> {
      const args = JSON.parse(rawArgs);
      switch (fnName) {
        case "search_bookmarks": {
          const result = await api.bookmarks.searchBookmarks({
            text: args.query,
            limit: args.limit ?? 10,
            includeContent: false,
          });
          return JSON.stringify(
            result.bookmarks.map((b: Record<string, unknown>) => ({
              id: b.id as string,
              title: b.title as string | null,
              url:
                (b.content as Record<string, unknown>).type === "link"
                  ? ((b.content as Record<string, unknown>).url as string)
                  : null,
              summary: b.summary as string | null,
              tags: (b.tags as Record<string, unknown>[]).map(
                (t) => t.name as string,
              ),
              archived: b.archived,
              favourited: b.favourited,
            })),
          );
        }
        case "get_bookmark": {
          const result = await api.bookmarks.getBookmark({
            bookmarkId: args.bookmarkId,
          });
          return JSON.stringify(result);
        }
        case "get_lists": {
          const result = await api.lists.list();
          return JSON.stringify(result.lists);
        }
        case "tag_bookmark": {
          await api.bookmarks.updateTags({
            bookmarkId: args.bookmarkId,
            attach: args.tags.map((t: string) => ({
              tagName: t,
              attachedBy: "ai",
            })),
            detach: [],
          });
          return `已添加标签: ${args.tags.join(", ")}`;
        }
        case "archive_bookmark": {
          await api.bookmarks.updateBookmark({
            bookmarkId: args.bookmarkId,
            archived: args.archived,
          });
          return args.archived ? "已归档" : "已取消归档";
        }
        case "favorite_bookmark": {
          await api.bookmarks.updateBookmark({
            bookmarkId: args.bookmarkId,
            favourited: args.favourited,
          });
          return args.favourited ? "已加收藏" : "已取消收藏";
        }
        case "add_bookmark_to_list": {
          await api.lists.addToList({
            bookmarkId: args.bookmarkId,
            listId: args.listId,
          });
          return "已加入文件夹";
        }
        case "update_note": {
          await api.bookmarks.updateBookmark({
            bookmarkId: args.bookmarkId,
            note: args.note,
          });
          return "笔记已更新";
        }
        default:
          return `未知工具: ${fnName}`;
      }
    }

    for (let i = 0; i < 10; i++) {
      const response = await openai.chat.completions.create({
        model: textModel,
        messages,
        tools,
        tool_choice: "auto",
      });

      const choice = response.choices[0];
      const responseMessage = choice.message;

      if (!responseMessage.tool_calls?.length) {
        for (const msg of messages) {
          if (msg.role === "tool" && typeof msg.content === "string") {
            try {
              const data = JSON.parse(msg.content);
              if (Array.isArray(data)) {
                for (const item of data) {
                  if (item.id && (item.title || item.url)) {
                    sources.push({
                      id: item.id,
                      title: item.title ?? null,
                      url: item.url ?? null,
                    });
                  }
                }
              }
            } catch {
              /* skip */
            }
          }
        }
        return c.json({
          answer: responseMessage.content || "",
          sources: sources.slice(0, 10),
        });
      }

      messages.push(responseMessage);

      for (const toolCall of responseMessage.tool_calls) {
        if (!("function" in toolCall)) continue;
        const fn = toolCall as {
          id: string;
          function: { name: string; arguments: string };
        };
        const result = await executeTool(
          fn.function.name,
          fn.function.arguments,
        );
        messages.push({ role: "tool", content: result, tool_call_id: fn.id });
      }
    }

    return c.json({ answer: "Agent 运行超时，请重试", sources: [] });
  },
);

export default app;
