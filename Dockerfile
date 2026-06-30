FROM node:24-slim

WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Copy workspace files
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml turbo.json ./
COPY packages/shared/package.json ./packages/shared/
COPY packages/shared-server/package.json ./packages/shared-server/
COPY packages/shared-react/package.json ./packages/shared-react/
COPY packages/db/package.json ./packages/db/
COPY packages/trpc/package.json ./packages/trpc/
COPY packages/api/package.json ./packages/api/
COPY packages/web/package.json ./packages/web/
COPY packages/plugins/package.json ./packages/plugins/
COPY packages/open-api/package.json ./packages/open-api/
COPY packages/sdk/package.json ./packages/sdk/

# Install dependencies
RUN corepack enable && pnpm install --frozen-lockfile

# Copy source code
COPY packages/shared ./packages/shared
COPY packages/shared-server ./packages/shared-server
COPY packages/shared-react ./packages/shared-react
COPY packages/db ./packages/db
COPY packages/trpc ./packages/trpc
COPY packages/api ./packages/api
COPY packages/web ./packages/web
COPY packages/plugins ./packages/plugins
COPY packages/open-api ./packages/open-api
COPY packages/sdk ./packages/sdk

# Build
RUN pnpm build --filter=@karakeep/web

CMD ["node", "/app/apps/web/server.js"]
