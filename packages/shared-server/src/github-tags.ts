/**
 * GitHub 项目分类系统
 *
 * 三层架构：
 *   1. Taxonomy — 分类树定义
 *   2. Rule Engine — GitHub topics → 分类映射
 *   3. Structured Output Schema — LLM 调用时的结构化输出约束
 *
 * 设计参考：raindrop-organizer (hybrid rule-based + AI categorization)
 * https://github.com/jackdonkey/raindrop-organizer
 */

// ===========================
// 1. TAXONOMY — 分类树
// ===========================

/** 顶级分类 */
export type TopCategory =
  | "dev-tools" // 开发者工具（CLI、编辑器、构建工具等）
  | "framework-lib" // 框架/库
  | "ai-ml" // AI/ML（Agent、LLM 工具、训练等）
  | "devops" // DevOps（CI/CD、容器、监控等）
  | "database" // 数据库/存储
  | "security" // 安全/渗透
  | "skills" // Skills/Instructions（Claude Code Skills 等）
  | "automation" // 自动化脚本/工具
  | "platform" // 平台/系统
  | "media" // 多媒体/设计
  | "web" // Web 应用/网站
  | "mobile" // 移动端
  | "documentation" // 文档/学习
  | "other"; // 其他

/** 分类定义 */
export interface CategoryDef {
  id: TopCategory;
  /** 中文显示名 */
  label: string;
  /** 分类描述 */
  desc: string;
  /** 匹配此分类的 GitHub topics 关键词 */
  topicKeywords: string[];
  /** 匹配的描述关键词 */
  descKeywords: string[];
  /** 父级分类（用于层级展示） */
  parent?: TopCategory;
}

export const TAXONOMY: Record<TopCategory, CategoryDef> = {
  skills: {
    id: "skills",
    label: "Skills / 指令集",
    desc: "Coding Agent 的技能集、指令集、Prompt 集合",
    topicKeywords: [
      "skill",
      "skills",
      "instructions",
      "prompt",
      "claude-code",
      "agent-skill",
      "codex",
    ],
    descKeywords: [
      "skill",
      "instruction",
      "prompt",
      "claude",
      "codex",
      "agent skill",
    ],
  },
  "ai-ml": {
    id: "ai-ml",
    label: "AI / 智能体",
    desc: "AI Agent 框架、LLM 工具、模型训练、推理引擎",
    topicKeywords: [
      "ai",
      "artificial-intelligence",
      "machine-learning",
      "deep-learning",
      "llm",
      "large-language-model",
      "gpt",
      "rag",
      "agent",
      "chatbot",
      "natural-language-processing",
      "nlp",
      "neural-network",
      "transformer",
      "embedding",
      "vector",
      "openai",
      "claude",
      "langchain",
    ],
    descKeywords: [
      "ai",
      "llm",
      "agent",
      "machine learning",
      "deep learning",
      "chatbot",
      "rag",
    ],
  },
  "dev-tools": {
    id: "dev-tools",
    label: "开发者工具",
    desc: "CLI 工具、编辑器扩展、构建工具、调试工具",
    topicKeywords: [
      "cli",
      "command-line",
      "terminal",
      "developer-tools",
      "developer-experience",
      "ide",
      "editor",
      "vscode",
      "vim",
      "neovim",
      "emacs",
      "build-tool",
      "bundler",
      "linter",
      "formatter",
      "debugger",
      "code-quality",
      "code-analysis",
      "static-analysis",
      "git",
      "version-control",
      "github-actions",
    ],
    descKeywords: [
      "cli",
      "command line",
      "developer tool",
      "terminal",
      "editor extension",
      "build",
    ],
  },
  "framework-lib": {
    id: "framework-lib",
    label: "框架 / 库",
    desc: "前端/后端/跨平台框架、代码库、SDK",
    topicKeywords: [
      "framework",
      "library",
      "sdk",
      "api",
      "react",
      "vue",
      "angular",
      "svelte",
      "nextjs",
      "nuxt",
      "express",
      "fastify",
      "nestjs",
      "spring",
      "django",
      "flask",
      "rails",
      "rust",
      "wasm",
      "webassembly",
      "css",
      "tailwind",
      "bootstrap",
      "ui-library",
    ],
    descKeywords: [
      "framework",
      "library",
      "sdk",
      "ui framework",
      "web framework",
    ],
  },
  devops: {
    id: "devops",
    label: "DevOps",
    desc: "CI/CD、容器编排、监控、基础设施即代码",
    topicKeywords: [
      "devops",
      "ci",
      "cd",
      "continuous-integration",
      "continuous-deployment",
      "docker",
      "kubernetes",
      "k8s",
      "container",
      "orchestration",
      "monitoring",
      "observability",
      "logging",
      "metrics",
      "prometheus",
      "infrastructure",
      "terraform",
      "ansible",
      "puppet",
      "chef",
      "deployment",
      "release",
      "helm",
    ],
    descKeywords: [
      "devops",
      "ci/cd",
      "docker",
      "kubernetes",
      "deployment",
      "monitoring",
      "infrastructure",
    ],
  },
  database: {
    id: "database",
    label: "数据库 / 存储",
    desc: "数据库引擎、缓存、对象存储、文件系统",
    topicKeywords: [
      "database",
      "db",
      "sql",
      "nosql",
      "postgresql",
      "mysql",
      "sqlite",
      "redis",
      "mongodb",
      "cassandra",
      "clickhouse",
      "elasticsearch",
      "cache",
      "storage",
      "object-storage",
      "file-system",
      "data-pipeline",
      "etl",
      "data-warehouse",
      "lake",
      "vector-database",
      "search-engine",
      "index",
    ],
    descKeywords: [
      "database",
      "storage",
      "cache",
      "sql",
      "nosql",
      "data pipeline",
    ],
  },
  security: {
    id: "security",
    label: "安全 / 渗透",
    desc: "网络安全、渗透测试、加密、身份认证",
    topicKeywords: [
      "security",
      "cybersecurity",
      "penetration-testing",
      "pentest",
      "vulnerability",
      "exploit",
      "malware",
      "ransomware",
      "encryption",
      "cryptography",
      "authentication",
      "authorization",
      "firewall",
      "ids",
      "ips",
      "waf",
      "zero-trust",
      "osint",
      "reconnaissance",
      "bug-bounty",
    ],
    descKeywords: [
      "security",
      "penetration test",
      "vulnerability",
      "encryption",
      "hacking",
    ],
  },
  automation: {
    id: "automation",
    label: "自动化",
    desc: "工作流自动化、爬虫、RPA、定时任务",
    topicKeywords: [
      "automation",
      "workflow",
      "pipeline",
      "crawler",
      "spider",
      "rpa",
      "robotic-process-automation",
      "scheduler",
      "cron",
      "scraping",
      "web-scraping",
      "data-extraction",
      "bot",
      "chatbot",
      "automation-framework",
      "home-automation",
      "iot",
      "smart-home",
    ],
    descKeywords: [
      "automation",
      "crawler",
      "scraping",
      "workflow",
      "bot",
      "rpa",
    ],
  },
  platform: {
    id: "platform",
    label: "平台 / 系统",
    desc: "操作系统、虚拟化、云平台、运行时",
    topicKeywords: [
      "os",
      "operating-system",
      "kernel",
      "linux",
      "windows",
      "virtualization",
      "vm",
      "hypervisor",
      "emulator",
      "cloud",
      "cloud-native",
      "serverless",
      "edge",
      "runtime",
      "vm",
      "jvm",
      "container-runtime",
      "paas",
      "iaas",
      "saas",
      "low-code",
      "no-code",
    ],
    descKeywords: [
      "platform",
      "operating system",
      "cloud",
      "virtualization",
      "runtime",
      "low-code",
    ],
  },
  media: {
    id: "media",
    label: "多媒体 / 设计",
    desc: "音视频处理、图像编辑、设计工具、3D",
    topicKeywords: [
      "audio",
      "video",
      "multimedia",
      "ffmpeg",
      "streaming",
      "image-processing",
      "computer-vision",
      "opencv",
      "design",
      "ui-ux",
      "figma",
      "design-system",
      "3d",
      "threejs",
      "webgl",
      "blender",
      "animation",
      "font",
      "typography",
      "icon",
    ],
    descKeywords: ["audio", "video", "image", "design", "3d", "multimedia"],
  },
  web: {
    id: "web",
    label: "Web 应用",
    desc: "Web 站点、CMS、博客引擎、静态站点",
    topicKeywords: [
      "website",
      "web-app",
      "web-application",
      "cms",
      "blog",
      "static-site",
      "ssg",
      "jamstack",
      "headless-cms",
      "ecommerce",
      "shop",
      "marketplace",
      "real-time",
      "websocket",
      "graphql",
      "rest-api",
      "pwa",
      "progressive-web-app",
      "seo",
    ],
    descKeywords: ["website", "web app", "cms", "blog", "ecommerce", "api"],
  },
  mobile: {
    id: "mobile",
    label: "移动端",
    desc: "iOS/Android 应用、跨平台移动开发",
    topicKeywords: [
      "ios",
      "android",
      "mobile",
      "swift",
      "kotlin",
      "react-native",
      "flutter",
      "ionic",
      "capacitor",
      "wearable",
      "watchos",
      "tvos",
      "mobile-app",
      "app-development",
    ],
    descKeywords: [
      "mobile",
      "ios",
      "android",
      "react native",
      "flutter",
      "app",
    ],
  },
  documentation: {
    id: "documentation",
    label: "文档 / 学习",
    desc: "技术文档、教程、知识库、电子书",
    topicKeywords: [
      "documentation",
      "docs",
      "wiki",
      "knowledge-base",
      "tutorial",
      "guide",
      "book",
      "ebook",
      "learning",
      "education",
      "course",
      "cheatsheet",
      "awesome-list",
      "awesome",
      "resources",
      "blog",
      "newsletter",
    ],
    descKeywords: [
      "documentation",
      "tutorial",
      "guide",
      "learning",
      "awesome",
      "wiki",
    ],
  },
  other: {
    id: "other",
    label: "其他",
    desc: "无法归类的项目",
    topicKeywords: [],
    descKeywords: [],
  },
};

/** 所有分类 ID 列表 */
export const ALL_CATEGORIES = Object.keys(TAXONOMY) as TopCategory[];

/** 分类列表（用于传给 LLM 的结构化描述） */
export function getCategoryListForPrompt(): string {
  return Object.values(TAXONOMY)
    .filter((c) => c.id !== "other")
    .map((c) => `- ${c.id}: ${c.label} — ${c.desc}`)
    .join("\n");
}

// ===========================
// 2. RULE ENGINE
// ===========================

export interface RuleMatch {
  category: TopCategory;
  confidence: number; // 0-100
  source: "topic" | "desc" | "name";
  matchedKeyword: string;
}

/**
 * 基于 GitHub topics 和元数据，做规则预分类。
 * 返回按置信度排序的匹配列表。
 */
/**
 * Words of length <= 3 that must NOT use substring matching, because they
 * appear as substrings of unrelated words (e.g. "go" in "goodbye", "ai" in
 * "tailwind", "db" in "adblock"). For these we require exact token equality.
 */
const SHORT_AMBIGUOUS_KEYWORDS = new Set([
  "go",
  "ai",
  "db",
  "vm",
  "os",
  "ci",
  "cd",
  "sql",
  "bot",
  "api",
  "cms",
  "rpa",
  "iot",
  "seo",
  "pwa",
  "css",
  "svg",
  "3d",
  "sdl",
]);

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Build a regex that matches `kw` as a whole word (alnum/hyphen boundary),
 * case-insensitive. Used for description/name matching so that short keywords
 * like "go" don't match "goodbye".
 */
function wordBoundaryRegex(kw: string): RegExp {
  // Treat hyphen as part of the token (many topic keywords are hyphenated),
  // so the boundary is anything that is not [a-z0-9-].
  return new RegExp(`(?<![a-z0-9-])${escapeRegExp(kw)}(?![a-z0-9-])`, "i");
}

export function classifyByRules(params: {
  topics: string[];
  description: string;
  name: string;
}): RuleMatch[] {
  const { topics, description, name } = params;
  const desc = (description ?? "").toLowerCase();
  const nameLower = (name ?? "").toLowerCase();
  const results: RuleMatch[] = [];

  for (const cat of ALL_CATEGORIES) {
    const def = TAXONOMY[cat];
    if (cat === "other") continue;

    // Topics 匹配：每个匹配 topic 累计 25 分。
    // 短/歧义词（go/ai/db…）要求 topic 完全相等，避免 "navigation-go"
    // 或 "google" 这类误命中；长词允许前缀包含（如 "react-native" 命中 "react"）。
    for (const kw of def.topicKeywords) {
      const kwLower = kw.toLowerCase();
      const isShort = SHORT_AMBIGUOUS_KEYWORDS.has(kwLower);
      const matched = topics.filter((t) => {
        const tl = t.toLowerCase();
        if (isShort) return tl === kwLower;
        return tl === kwLower || tl.includes(kwLower);
      });
      if (matched.length > 0) {
        results.push({
          category: cat,
          confidence: Math.min(matched.length * 25, 90),
          source: "topic",
          matchedKeyword: kw,
        });
      }
    }

    // 描述匹配：用词边界正则，避免 "go" 命中 "goodbye"
    for (const kw of def.descKeywords) {
      if (wordBoundaryRegex(kw).test(desc)) {
        results.push({
          category: cat,
          confidence: 15,
          source: "desc",
          matchedKeyword: kw,
        });
      }
    }

    // 项目名匹配：同样用词边界
    for (const kw of def.topicKeywords) {
      if (wordBoundaryRegex(kw).test(nameLower)) {
        results.push({
          category: cat,
          confidence: 10,
          source: "name",
          matchedKeyword: kw,
        });
      }
    }
  }

  // 按分类聚合置信度
  const aggregated = new Map<TopCategory, RuleMatch>();
  for (const r of results) {
    const existing = aggregated.get(r.category);
    if (existing) {
      existing.confidence = Math.min(existing.confidence + r.confidence, 95);
    } else {
      aggregated.set(r.category, { ...r });
    }
  }

  // 按置信度降序排序
  return Array.from(aggregated.values()).sort(
    (a, b) => b.confidence - a.confidence,
  );
}

// ===========================
// 3. STRUCTURED OUTPUT SCHEMA
// ===========================

/**
 * LLM 结构化输出的结果类型。
 * 使用此类型作为 function calling / structured output 的 schema。
 */
export interface GitHubClassificationResult {
  /** 主要分类（从 taxonomy 中选择） */
  primaryCategory: TopCategory;
  /** 分类置信度 0-100 */
  categoryConfidence: number;
  /** humanTags: 中文显示标签，按重要性排序 */
  humanTags: string[];
  /** humanSummary: 30-60字中文简介 */
  humanSummary: string;
  /** valueScore */
  valueScore: "high" | "mid" | "low";
  /** agentTags: 英文标签，用于 Agent 搜索 */
  agentTags: string[];
  /** 项目一句话定位 */
  oneLiner: string;
  /** 详细分析 */
  dossier: {
    overview: string;
    keyFeatures: string[];
    techStack: string[];
    useCases: string[];
    pros: string[];
    cons: string[];
    maturity: "active" | "stable" | "inactive";
  };
}

/**
 * 构建结构化输出的 system prompt。
 * 使用 function calling / structured output 方式调用时，
 * 以此作为 schema 定义传给 LLM API。
 */
export function buildClassificationSystemPrompt(): string {
  return `你是一个 GitHub 项目分类专家。你需要分析项目的元数据和 README，输出结构化分类结果。

## 分类树（选择最匹配的一个主要分类）

${getCategoryListForPrompt()}

## 分类规则

1. 先看 GitHub topics（最可靠的信号）
2. 再看项目描述和 README
3. 核心原则："这个项目是什么"——不是它用了什么技术
4. 宁缺毋滥：低置信度的标签不输出

## 标签规则

### humanTags（中文）
- 每个标签是独立概念
- 最核心的标签放第一位
- 技术/产品原名（skills、cli、react 等）不翻译
- 宁缺毋滥：1 个精准标签 > 5 个凑数的

### agentTags（英文）
- 面向 AI Coding Agent 的搜索标签
- 精准描述项目用途
- 让 Agent 一眼知道这能不能解决当前问题`;
}

/**
 * 构建 user prompt。
 */
export function buildClassificationUserPrompt(params: {
  name: string;
  description: string | null;
  language: string | null;
  stars: number | null;
  topics: string[] | null;
  readmeContent: string;
}): string {
  return `项目名称：${params.name}
描述：${params.description ?? "无"}
语言：${params.language ?? "未知"}
Stars：${params.stars ?? "未知"}
Topics：${params.topics?.join(", ") ?? "无"}

README 内容：
${params.readmeContent}

请输出分类结果。`;
}
