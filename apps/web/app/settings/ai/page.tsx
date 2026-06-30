import type { Metadata } from "next";
import AISettings from "@/components/settings/AISettings";
import AiProviderConfig from "@/components/admin/AiProviderConfig";
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
  const isAdmin = session?.user?.role === "admin";

  return (
    <>
      <AISettings isAdmin={isAdmin} />
      {isAdmin && (
        <div className="border-t pt-8">
          <AiProviderConfig isAdmin={isAdmin} />
        </div>
      )}
    </>
  );
}
