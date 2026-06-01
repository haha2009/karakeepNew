import type { Metadata } from "next";
import AiProviderConfig from "@/components/admin/AiProviderConfig";
import AISettings from "@/components/settings/AISettings";
import { useTranslation } from "@/lib/i18n/server";
import { getServerAuthSession } from "@/server/auth";

export async function generateMetadata(): Promise<Metadata> {
  // oxlint-disable-next-line rules-of-hooks
  const { t } = await useTranslation();
  return {
    title: `${t("settings.ai.ai_settings")} | Karakeep`,
  };
}

export default async function AISettingsPage() {
  const session = await getServerAuthSession();

  return (
    <div className="flex flex-col gap-8">
      <AISettings />
      {session?.user?.role === "admin" && (
        <div className="border-t pt-8">
          <AiProviderConfig />
        </div>
      )}
    </div>
  );
}
