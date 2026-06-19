import { redirect } from "next/navigation";
import AllLists from "@/components/dashboard/sidebar/AllLists";
import MobileSidebar from "@/components/shared/sidebar/MobileSidebar";
import Sidebar from "@/components/shared/sidebar/Sidebar";
import SidebarLayout from "@/components/shared/sidebar/SidebarLayout";
import { Separator } from "@/components/ui/separator";
import { ReaderSettingsProvider } from "@/lib/readerSettings";
import { UserSettingsContextProvider } from "@/lib/userSettings";
import { api } from "@/server/api/client";
import { getQueryClient, serverTrpc } from "@/server/api/trpc";
import { getServerAuthSession } from "@/server/auth";
import { TRPCError } from "@trpc/server";
import { dehydrate, HydrationBoundary } from "@tanstack/react-query";
import { TFunction } from "i18next";
import {
  Archive,
  Brain,
  ClipboardList,
  Database,
  Highlighter,
  Tag,
  GitFork,
} from "lucide-react";
import { tryCatch } from "@karakeep/shared/tryCatch";

export default async function Dashboard({
  children,
  modal,
}: Readonly<{
  children: React.ReactNode;
  modal: React.ReactNode;
}>) {
  const session = await getServerAuthSession();
  if (!session) {
    redirect("/");
  }

  const [lists, userSettings] = await Promise.all([
    tryCatch(api.lists.list()),
    tryCatch(api.users.settings()),
  ]);

  if (userSettings.error) {
    if (userSettings.error instanceof TRPCError) {
      if (
        userSettings.error.code === "NOT_FOUND" ||
        userSettings.error.code === "UNAUTHORIZED"
      ) {
        redirect("/logout");
      }
    }
    throw userSettings.error;
  }

  if (lists.error) {
    throw lists.error;
  }

  // Pre-fill the server-side QueryClient cache so React Query on the client
  // hydrates with the exact same data, preventing hydration mismatches.
  const queryClient = getQueryClient();
  const listsOptions = serverTrpc.lists.list.queryOptions();
  queryClient.setQueryData(listsOptions.queryKey, lists.data);
  const dehydratedState = dehydrate(queryClient);

  const items = (t: TFunction) =>
    [
      {
        name: "采集",
        icon: <Database size={18} />,
        path: "/dashboard/bookmarks",
      },
      {
        name: "AI 理解",
        icon: <Brain size={18} />,
        path: "/dashboard/ai-insights",
      },
      {
        name: t("common.tags"),
        icon: <Tag size={18} />,
        path: "/dashboard/tags",
      },
      {
        name: t("common.highlights"),
        icon: <Highlighter size={18} />,
        path: "/dashboard/highlights",
      },
      {
        name: t("common.archive"),
        icon: <Archive size={18} />,
        path: "/dashboard/archive",
      },
      {
        name: "GitHub Projects",
        icon: <GitFork size={18} />,
        path: "/dashboard/projects",
      },
    ].flat();

  const mobileSidebar = (t: TFunction) => [
    ...items(t),
    {
      name: t("lists.all_lists"),
      icon: <ClipboardList size={18} />,
      path: "/dashboard/lists",
    },
  ];

  return (
    <HydrationBoundary state={dehydratedState}>
      <UserSettingsContextProvider userSettings={userSettings.data}>
        <ReaderSettingsProvider>
          <SidebarLayout
            sidebar={
              <Sidebar
                items={items}
                extraSections={
                  <>
                    <Separator />
                    <AllLists initialData={lists.data} />
                  </>
                }
              />
            }
            mobileSidebar={<MobileSidebar items={mobileSidebar} />}
            modal={modal}
          >
            {children}
          </SidebarLayout>
        </ReaderSettingsProvider>
      </UserSettingsContextProvider>
    </HydrationBoundary>
  );
}
