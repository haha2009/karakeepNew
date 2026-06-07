"use client";

import { useRef, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { Bot, Loader2, MessageSquare, Send, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Textarea } from "@/components/ui/textarea";

interface Message {
  role: "user" | "assistant";
  content: string;
  sources?: {
    id: string;
    title: string | null;
    url: string | null;
  }[];
}

async function sendChatMessage(message: string) {
  const res = await fetch("/api/v1/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: "Request failed" }));
    throw new Error(err.error || `Error: ${res.status}`);
  }
  return res.json() as Promise<{
    answer: string;
    sources: { id: string; title: string | null; url: string | null }[];
  }>;
}

export default function ChatSidebar() {
  const [isOpen, setIsOpen] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const inputRef = useRef<HTMLTextAreaElement>(null);

  const chatMutation = useMutation({
    mutationFn: sendChatMessage,
    onMutate: async (text) => {
      setMessages((prev) => [...prev, { role: "user", content: text }]);
    },
    onSuccess: (data) => {
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: data.answer, sources: data.sources },
      ]);
    },
    onError: (error) => {
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: error.message || "出错了，请重试" },
      ]);
    },
  });

  const sendMessage = () => {
    const text = input.trim();
    if (!text || chatMutation.isPending) return;
    setInput("");
    chatMutation.mutate(text);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  };

  return (
    <>
      {!isOpen && (
        <Button
          size="icon"
          variant="outline"
          onClick={() => setIsOpen(true)}
          className="fixed bottom-4 right-4 z-50 h-10 w-10 rounded-full shadow-lg"
          title="AI 助手"
        >
          <MessageSquare className="h-5 w-5" />
        </Button>
      )}

      {isOpen && (
        <div className="fixed bottom-0 right-0 z-50 flex h-[calc(100dvh-64px)] w-full max-w-md flex-col border-l bg-background shadow-xl">
          <div className="flex items-center justify-between border-b px-4 py-3">
            <div className="flex items-center gap-2 text-sm font-medium">
              <Bot className="h-4 w-4" />
              AI 助手
            </div>
            <Button
              size="icon"
              variant="ghost"
              onClick={() => setIsOpen(false)}
              className="h-8 w-8"
            >
              <X className="h-4 w-4" />
            </Button>
          </div>

          <ScrollArea className="flex-1 p-4">
            {messages.length === 0 && (
              <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
                问关于你收藏的问题
              </div>
            )}
            <div className="space-y-4">
              {messages.map((msg, i) => (
                <div
                  key={i}
                  className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}
                >
                  <div
                    className={`max-w-[85%] rounded-lg px-3 py-2 text-sm ${
                      msg.role === "user"
                        ? "bg-primary text-primary-foreground"
                        : "bg-muted"
                    }`}
                  >
                    <div className="whitespace-pre-wrap">{msg.content}</div>
                    {msg.sources && msg.sources.length > 0 && (
                      <div className="mt-2 border-t pt-1.5 text-xs text-muted-foreground">
                        {msg.sources.map(
                          (s) =>
                            (s.title || s.url) && (
                              <a
                                key={s.id}
                                href={s.url || "#"}
                                target="_blank"
                                rel="noreferrer"
                                className="mr-2 inline-block hover:underline"
                              >
                                📖 {s.title || "链接"}
                              </a>
                            ),
                        )}
                      </div>
                    )}
                  </div>
                </div>
              ))}
              {chatMutation.isPending && (
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <Loader2 className="h-3 w-3 animate-spin" />
                  思考中...
                </div>
              )}
            </div>
          </ScrollArea>

          <div className="border-t p-3">
            <div className="flex gap-2">
              <Textarea
                ref={inputRef}
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="问关于收藏的问题..."
                className="min-h-9 resize-none text-sm"
                rows={1}
                disabled={chatMutation.isPending}
              />
              <Button
                size="icon"
                onClick={sendMessage}
                disabled={chatMutation.isPending || !input.trim()}
                className="h-9 w-9 shrink-0"
              >
                <Send className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
