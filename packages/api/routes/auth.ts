import { Hono } from "hono";

import { authMiddleware } from "../middlewares/auth";

const app = new Hono()
  .use(authMiddleware)

  // GET /auth/me — returns current auth info (no tRPC call, works with any scope)
  .get("/me", async (c) => {
    const user = c.var.ctx.user;
    const auth = c.var.ctx.auth;
    return c.json(
      {
        id: user.id,
        name: user.name ?? null,
        email: user.email ?? null,
        localUser: true,
        auth: auth
          ? {
              type: auth.type,
              ...(auth.type === "apiKey" ? { scopes: auth.scopes } : {}),
            }
          : null,
      },
      200,
    );
  });

export default app;
