"use client";

import React, { useState } from "react";
import { useRouter } from "next/navigation";
import { Link as LinkIcon, MoreHorizontal, Plus, Rss } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useTranslation } from "@/lib/i18n/client";

import EditorCard from "./EditorCard";

export default function AddDropdownMenu() {
  const { t } = useTranslation();
  const router = useRouter();
  const [showEditor, setShowEditor] = useState(false);

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="default" size="sm" className="gap-1">
            <Plus className="size-4" />
            <span className="hidden sm:inline">{t("actions.add")}</span>
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onSelect={() => setShowEditor(true)}>
            <LinkIcon className="mr-2 size-4" />
            {t("add.manual_url")}
          </DropdownMenuItem>
          <DropdownMenuItem onSelect={() => router.push("/dashboard/settings")}>
            <Rss className="mr-2 size-4" />
            {t("add.rss_feed")}
          </DropdownMenuItem>
          <DropdownMenuItem disabled>
            <MoreHorizontal className="mr-2 size-4" />
            {t("add.other")}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      {showEditor && (
        <div className="mt-4">
          <EditorCard />
        </div>
      )}
    </>
  );
}
