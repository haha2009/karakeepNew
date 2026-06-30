"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { AdminCard } from "@/components/admin/AdminCard";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/components/ui/sonner";
import { useTRPC } from "@karakeep/shared-react/trpc";
import { ChevronDown } from "lucide-react";

interface ProviderOutput {
  id: string;
  name: string;
  apiKey: string | null;
  apiKeyDisplay: string | null;
  baseUrl: string | null;
  textModel: string;
  imageModel: string | null;
  proxyUrl: string | null;
  outputSchema: "json" | "structured" | "plain";
  isDefault: boolean;
  isActive: boolean;
  createdAt: Date | null;
  updatedAt: Date | null;
}

interface ProviderFormData {
  id?: string;
  name: string;
  apiKey: string;
  baseUrl: string;
  textModel: string;
  imageModel: string;
  proxyUrl: string;
  outputSchema: "json" | "structured" | "plain";
  isDefault: boolean;
  isActive: boolean;
}

const emptyForm: ProviderFormData = {
  name: "",
  apiKey: "",
  baseUrl: "",
  textModel: "deepseek-chat",
  imageModel: "",
  proxyUrl: "",
  outputSchema: "json",
  isDefault: false,
  isActive: true,
};

export default function AiProviderConfig({ isAdmin }: { isAdmin: boolean }) {
  if (!isAdmin) return null;
  const api = useTRPC();
  const queryClient = useQueryClient();

  const { data: providers, isLoading } = useQuery(
    api.admin.listAiProviders.queryOptions({}),
  );

  const [editingId, setEditingId] = useState<string | null>(null);
  const [form, setForm] = useState<ProviderFormData>(emptyForm);
  const [showForm, setShowForm] = useState(false);
  const [jsonInput, setJsonInput] = useState("");
  const [showJsonImporter, setShowJsonImporter] = useState(false);
  const [testResult, setTestResult] = useState<{
    success?: boolean;
    latencyMs?: number;
    error?: string;
  } | null>(null);

  const createMutation = useMutation({
    ...api.admin.createAiProvider.mutationOptions(),
    onSuccess: () => {
      queryClient.invalidateQueries(api.admin.listAiProviders.pathFilter());
      setShowForm(false);
      setEditingId(null);
      setForm(emptyForm);
    },
  });

  const updateMutation = useMutation({
    ...api.admin.updateAiProvider.mutationOptions(),
    onSuccess: () => {
      queryClient.invalidateQueries(api.admin.listAiProviders.pathFilter());
      setShowForm(false);
      setEditingId(null);
      setForm(emptyForm);
    },
  });

  const testMutation = useMutation({
    ...api.admin.testAiProvider.mutationOptions(),
    onSuccess: (result) => {
      if (result.ok) {
        setTestResult({ success: true, latencyMs: result.latencyMs });
        if (editingId) {
          const existing = providers?.find((p) => p.id === editingId);
          const apiKeyToSave = form.apiKey || existing?.apiKey || undefined;
          if (existing && apiKeyToSave && apiKeyToSave !== existing.apiKey) {
            updateMutation.mutate({
              id: editingId,
              name: form.name || undefined,
              apiKey: apiKeyToSave,
              baseUrl: form.baseUrl || undefined,
              textModel: form.textModel || undefined,
              imageModel: form.imageModel || undefined,
              proxyUrl: form.proxyUrl || undefined,
              outputSchema: form.outputSchema,
              isDefault: form.isDefault,
              isActive: form.isActive,
            });
          }
        }
      } else {
        setTestResult({ error: result.error ?? "连接失败" });
      }
    },
  });

  const removeMutation = useMutation({
    ...api.admin.removeAiProvider.mutationOptions(),
    onSuccess: () => {
      queryClient.invalidateQueries(api.admin.listAiProviders.pathFilter());
    },
  });

  const autoDefaultMutation = useMutation({
    ...api.admin.setDefaultAiProvider.mutationOptions(),
    onSuccess: () => {
      queryClient.invalidateQueries(api.admin.listAiProviders.pathFilter());
    },
  });

  const setDefaultMutation = useMutation({
    ...api.admin.setDefaultAiProvider.mutationOptions(),
    onSuccess: () => {
      queryClient.invalidateQueries(api.admin.listAiProviders.pathFilter());
    },
  });

  const handleEdit = (p: ProviderOutput) => {
    setEditingId(p.id);
    setForm({
      id: p.id,
      name: p.name,
      apiKey: p.apiKey ?? "",
      baseUrl: p.baseUrl ?? "",
      textModel: p.textModel,
      imageModel: p.imageModel ?? "",
      proxyUrl: p.proxyUrl ?? "",
      outputSchema: p.outputSchema,
      isDefault: p.isDefault,
      isActive: p.isActive,
    });
    setShowForm(true);
    setTestResult(null);
  };

  const handleAdd = () => {
    setEditingId(null);
    setForm(emptyForm);
    setShowForm(true);
    setTestResult(null);
  };

  const handleSave = () => {
    setTestResult(null);
    if (editingId) {
      updateMutation.mutate({
        id: editingId,
        name: form.name || undefined,
        apiKey: form.apiKey || undefined,
        baseUrl: form.baseUrl || undefined,
        textModel: form.textModel || undefined,
        imageModel: form.imageModel || undefined,
        proxyUrl: form.proxyUrl || undefined,
        outputSchema: form.outputSchema,
        isDefault: form.isDefault,
        isActive: form.isActive,
      });
    } else {
      createMutation.mutate({
        name: form.name || undefined,
        apiKey: form.apiKey || undefined,
        baseUrl: form.baseUrl || undefined,
        textModel: form.textModel || undefined,
        imageModel: form.imageModel || undefined,
        proxyUrl: form.proxyUrl || undefined,
        outputSchema: form.outputSchema,
        isDefault: form.isDefault,
        isActive: form.isActive,
      });
    }
  };

  const handleTest = () => {
    setTestResult(null);
    const payload: { baseUrl?: string; apiKey?: string; textModel?: string } = {
      baseUrl: form.baseUrl || undefined,
      textModel: form.textModel || undefined,
    };
    let resolvedApiKey: string | undefined;
    if (editingId && providers) {
      const existing = providers.find((p) => p.id === editingId);
      const hasNewKey = !!form.apiKey?.trim();
      resolvedApiKey = hasNewKey ? form.apiKey.trim() : existing?.apiKey ?? undefined;
    } else {
      resolvedApiKey = form.apiKey || undefined;
    }
    payload.apiKey = resolvedApiKey;
    testMutation.mutate(payload);
  };

  const handleRemove = async (id: string) => {
    const target = providers?.find((p) => p.id === id);
    const wasDefault = target?.isDefault;
    if (!confirm("确定删除此供应商？")) return;
    removeMutation.mutate({ id }, {
      onSuccess: async () => {
        if (wasDefault) {
          await queryClient.invalidateQueries(api.admin.listAiProviders.pathFilter());
          const updated = queryClient.getQueryData(
            api.admin.listAiProviders.queryOptions({}).queryKey,
          ) as Array<{ id: string; isDefault: boolean }> | undefined;
          const remaining = updated?.filter((p) => p.id !== id && p.id !== "default");
          if (remaining && remaining.length > 0 && !remaining.some((p) => p.isDefault)) {
            autoDefaultMutation.mutate({ id: remaining[0].id });
          }
        }
      },
    });
  };

  const handleSetDefault = (id: string) => {
    setDefaultMutation.mutate({ id });
  };

  const handleImportConfig = (jsonText: string) => {
    try {
      const parsed = JSON.parse(jsonText);
      const cfg = parsed.env ?? parsed.ENV ?? parsed;

      const baseUrl =
        (typeof cfg.ANTHROPIC_BASE_URL === "string"
          ? cfg.ANTHROPIC_BASE_URL
          : typeof cfg.baseUrl === "string"
            ? cfg.baseUrl
            : typeof cfg.OPENAI_BASE_URL === "string"
              ? cfg.OPENAI_BASE_URL
              : "") ||
        (typeof cfg.baseURL === "string" ? cfg.baseURL : "");

      const apiKey =
        (typeof cfg.ANTHROPIC_API_KEY === "string"
          ? cfg.ANTHROPIC_API_KEY
          : typeof cfg.API_KEY === "string"
            ? cfg.API_KEY
            : typeof cfg.apiKey === "string"
              ? cfg.apiKey
              : "") ||
        "";

      const model =
        (typeof cfg.ANTHROPIC_MODEL === "string"
          ? cfg.ANTHROPIC_MODEL
          : typeof cfg.ANTHROPIC_DEFAULT_SONNET_MODEL === "string"
            ? cfg.ANTHROPIC_DEFAULT_SONNET_MODEL
            : typeof cfg.model === "string"
              ? cfg.model
              : "") ||
        "";

      const opusModel =
        typeof cfg.ANTHROPIC_DEFAULT_OPUS_MODEL === "string"
          ? cfg.ANTHROPIC_DEFAULT_OPUS_MODEL
          : undefined;
      const sonnetModel =
        typeof cfg.ANTHROPIC_DEFAULT_SONNET_MODEL === "string"
          ? cfg.ANTHROPIC_DEFAULT_SONNET_MODEL
          : undefined;
      const haikuModel =
        typeof cfg.ANTHROPIC_DEFAULT_HAIKU_MODEL === "string"
          ? cfg.ANTHROPIC_DEFAULT_HAIKU_MODEL
          : undefined;
      const fableModel =
        typeof cfg.ANTHROPIC_DEFAULT_FABLE_MODEL === "string"
          ? cfg.ANTHROPIC_DEFAULT_FABLE_MODEL
          : undefined;

      const models = [opusModel, sonnetModel, haikuModel, fableModel, model].filter(
        Boolean,
      ) as string[];
      const displayModel = models[0] || "deepseek-chat";

      const name =
        (typeof cfg.effortLevel === "string" ? cfg.effortLevel : "") ||
        (baseUrl ? new URL(baseUrl).hostname : "导入供应商");

      setForm({
        name,
        apiKey,
        baseUrl,
        textModel: displayModel,
        imageModel: "",
        proxyUrl: "",
        outputSchema: "json",
        isDefault: false,
        isActive: true,
      });
      setEditingId(null);
      setShowForm(true);
      setTestResult(null);
    } catch {
      toast({
        description: "JSON 格式错误，请检查输入",
        variant: "destructive",
      });
    }
  };

  const isLoadingAny =
    createMutation.isPending ||
    updateMutation.isPending ||
    testMutation.isPending ||
    removeMutation.isPending ||
    setDefaultMutation.isPending;

  if (isLoading) {
    return <div className="text-sm text-muted-foreground">加载中...</div>;
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold">AI 供应商管理</h2>
          <p className="text-sm text-muted-foreground">
            管理多个 AI 供应商，推理时自动使用默认供应商。
          </p>
        </div>
        {!showForm && (
          <Button onClick={handleAdd}>+ 添加供应商</Button>
        )}
      </div>

      {showForm && (
        <AdminCard>
          <div className="flex flex-col gap-4">
            <h3 className="font-medium">
              {editingId ? "编辑供应商" : "添加供应商"}
            </h3>

            <div className="border-t pt-2">
              <button
                type="button"
                onClick={() => setShowJsonImporter(!showJsonImporter)}
                className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
              >
                <ChevronDown
                  className={`size-4 transition-transform ${showJsonImporter ? "rotate-180" : ""}`}
                />
                批量导入（JSON 配置）
              </button>
              {showJsonImporter && (
                <div className="mt-3 space-y-2">
                  <Textarea
                    value={jsonInput}
                    onChange={(e) => setJsonInput(e.target.value)}
                    placeholder={`粘贴环境变量 JSON，例如：\n{\n  "effortLevel": "high",\n  "env": {\n    "ANTHROPIC_API_KEY": "sk-...",\n    "ANTHROPIC_BASE_URL": "https://...",\n    "ANTHROPIC_MODEL": "model-name"\n  }\n}`}
                    rows={6}
                    className="font-mono text-xs"
                  />
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => handleImportConfig(jsonInput)}
                    disabled={!jsonInput.trim()}
                  >
                    解析并填充
                  </Button>
                </div>
              )}
            </div>

            <div className="grid gap-2">
              <Label htmlFor="name">名称 *</Label>
              <Input
                id="name"
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
                placeholder="如 DeepSeek"
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="apiKey">API Key</Label>
              <Input
                id="apiKey"
                type="password"
                value={form.apiKey}
                onChange={(e) => setForm({ ...form, apiKey: e.target.value })}
                placeholder={editingId ? "留空则保留当前 Key" : "输入 API Key"}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="baseUrl">Base URL</Label>
              <Input
                id="baseUrl"
                value={form.baseUrl}
                onChange={(e) => setForm({ ...form, baseUrl: e.target.value })}
                placeholder="https://api.openai.com/v1"
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="textModel">文本模型 *</Label>
              <Input
                id="textModel"
                value={form.textModel}
                onChange={(e) => setForm({ ...form, textModel: e.target.value })}
                placeholder="deepseek-chat"
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="imageModel">图片模型</Label>
              <Input
                id="imageModel"
                value={form.imageModel}
                onChange={(e) => setForm({ ...form, imageModel: e.target.value })}
                placeholder="同文本模型"
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="proxyUrl">代理地址</Label>
              <Input
                id="proxyUrl"
                value={form.proxyUrl}
                onChange={(e) => setForm({ ...form, proxyUrl: e.target.value })}
                placeholder="http://127.0.0.1:1080 (可选)"
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="outputSchema">输出格式</Label>
              <Select
                value={form.outputSchema}
                onValueChange={(v) =>
                  setForm({ ...form, outputSchema: v as "json" | "structured" | "plain" })
                }
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="json">JSON</SelectItem>
                  <SelectItem value="structured">Structured</SelectItem>
                  <SelectItem value="plain">Plain Text</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex items-center gap-6">
              <label className="flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={form.isActive}
                  onChange={(e) =>
                    setForm({ ...form, isActive: e.target.checked })
                  }
                />
                <span className="text-sm">启用</span>
              </label>
              <label className="flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={form.isDefault}
                  onChange={(e) =>
                    setForm({ ...form, isDefault: e.target.checked })
                  }
                />
                <span className="text-sm">设为默认</span>
              </label>
            </div>

            {testResult && (
              <div
                className={`text-sm ${testResult.success ? "text-green-600" : "text-red-600"}`}
              >
                {testResult.success
                  ? `连接成功（${testResult.latencyMs}ms）`
                  : `测试失败：${testResult.error}`}
              </div>
            )}

            <div className="flex items-center gap-3">
              <Button
                onClick={handleSave}
                disabled={isLoadingAny}
              >
                {isLoadingAny ? "保存中..." : "保存"}
              </Button>
              {editingId && (
                <Button
                  variant="secondary"
                  onClick={handleTest}
                  disabled={isLoadingAny}
                >
                  测试连接
                </Button>
              )}
              <Button
                variant="ghost"
                onClick={() => {
                  setShowForm(false);
                  setEditingId(null);
                  setForm(emptyForm);
                  setTestResult(null);
                }}
              >
                取消
              </Button>
            </div>
          </div>
        </AdminCard>
      )}

      {!showForm && (!providers || providers.length === 0) && (
        <div className="text-center text-sm text-muted-foreground py-8">
          还没有配置 AI 供应商。点击上方按钮添加。
        </div>
      )}

  {!showForm &&
        providers?.map((p) => (
          <AdminCard key={p.id}>
            <div className="flex items-start justify-between">
              <div className="flex-1">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-medium">{p.name}</span>
                  {p.isDefault && (
                    <span className="text-xs bg-amber-100 text-amber-700 px-2 py-0.5 rounded">
                      默认
                    </span>
                  )}
                  {p.isActive && (
                    <span className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded">
                      活跃
                    </span>
                  )}
                </div>
                <p className="text-xs text-muted-foreground mt-1">
                  API: {p.apiKey || "未设置"}
                </p>
                <p className="text-xs text-muted-foreground">
                  {p.baseUrl || "(默认地址)"} / {p.textModel}
                </p>
              </div>
              <div className="flex items-center gap-2">
                {p.id !== "default" && !p.isDefault && p.isActive && (
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => handleSetDefault(p.id)}
                    disabled={isLoadingAny}
                  >
                    设为默认
                  </Button>
                )}
                {p.id !== "default" && (
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => handleEdit(p as ProviderOutput)}
                  >
                    编辑
                  </Button>
                )}
                <Button
                  size="sm"
                  variant="destructive"
                  onClick={() => handleRemove(p.id)}
                  disabled={isLoadingAny}
                >
                  删除
                </Button>
              </div>
            </div>
          </AdminCard>
        ))}
    </div>
  );
}
