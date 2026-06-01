"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
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
import { useTRPC } from "@karakeep/shared-react/trpc";

export default function AiProviderConfig() {
  const api = useTRPC();
  const queryClient = useQueryClient();

  const { data, isLoading: _isLoading } = useQuery({
    ...api.admin.getProviderConfig.queryOptions(),
  });

  const [baseUrl, setBaseUrl] = useState("");
  const [apiKey, setApiKey] = useState("");
  const [textModel, setTextModel] = useState("");
  const [outputSchema, setOutputSchema] = useState("json");
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    if (data) {
      setBaseUrl(data.baseUrl ?? "");
      setApiKey("");
      setTextModel(data.textModel ?? "");
      setOutputSchema(data.outputSchema ?? "json");
    }
  }, [data]);

  const saveMutation = useMutation({
    ...api.admin.saveProviderConfig.mutationOptions(),
    onSuccess: () => {
      setSaved(true);
      queryClient.invalidateQueries(api.admin.getProviderConfig.pathFilter());
      setTimeout(() => setSaved(false), 2000);
    },
  });

  const handleSave = () => {
    saveMutation.mutate({
      baseUrl: baseUrl || undefined,
      apiKey: apiKey || undefined,
      textModel: textModel || undefined,
      outputSchema: outputSchema as "structured" | "json" | "plain",
    });
  };

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h2 className="text-lg font-semibold">AI 提供商配置</h2>
        <p className="text-sm text-muted-foreground">
          保存后将覆盖 .env 环境变量中的配置，AI 推理 Worker
          每次运行优先读取此配置。 留空字段会使用环境变量的值。
        </p>
      </div>

      <AdminCard>
        <div className="flex flex-col gap-4">
          <div className="grid gap-2">
            <Label htmlFor="baseUrl">API Base URL</Label>
            <Input
              id="baseUrl"
              type="text"
              value={baseUrl}
              onChange={(e) => setBaseUrl(e.target.value)}
              placeholder="https://api.openai.com/v1"
            />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="apiKey">API Key</Label>
            <Input
              id="apiKey"
              type="password"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder={
                data?.hasApiKey ? "留空则保留当前 Key" : "输入新的 API Key"
              }
            />
            {data?.apiKeyDisplay && (
              <p className="text-xs text-muted-foreground">
                当前 Key（仅显示首尾）: {data.apiKeyDisplay}
              </p>
            )}
          </div>

          <div className="grid gap-2">
            <Label htmlFor="textModel">文本模型</Label>
            <Input
              id="textModel"
              type="text"
              value={textModel}
              onChange={(e) => setTextModel(e.target.value)}
              placeholder="deepseek-v4-pro"
            />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="outputSchema">输出格式</Label>
            <Select value={outputSchema} onValueChange={setOutputSchema}>
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

          <div className="flex items-center gap-3 pt-2">
            <Button onClick={handleSave} disabled={saveMutation.isPending}>
              {saveMutation.isPending ? "保存中..." : "保存"}
            </Button>
            {saved && <span className="text-sm text-green-600">已保存 ✓</span>}
            {saveMutation.isError && (
              <span className="text-sm text-red-600">保存失败</span>
            )}
          </div>
        </div>
      </AdminCard>
    </div>
  );
}
