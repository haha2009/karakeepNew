import { db } from "@karakeep/db";
import { createCallerFactory } from "@karakeep/trpc";
import { appRouter } from "@karakeep/trpc/routers/_app";

async function main() {
  const createCaller = createCallerFactory(appRouter);

  const ctx = {
    user: {
      id: "j7wbv3wle3eklvqvlmc6crxg",
      name: "yuanxi",
      email: "yuanxi0209s@gmail.com",
      role: "admin" as const,
    },
    auth: { type: "session" as const },
    db,
    req: { ip: "127.0.0.1" },
  };

  const api = createCaller(ctx);

  console.log("Triggering re-crawl for all success links...");
  await api.admin.recrawlLinks({ crawlStatus: "success", runInference: false });
  console.log("Done! Re-crawl jobs enqueued.");
}

main().catch(console.error);
