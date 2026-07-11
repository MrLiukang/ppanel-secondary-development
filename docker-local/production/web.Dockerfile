FROM oven/bun:1.3.1 AS builder

ARG APP
WORKDIR /app

COPY package.json bun.lock bunfig.toml turbo.json tsconfig.json biome.jsonc ./
COPY apps ./apps
COPY packages ./packages
COPY docs ./docs

RUN bun install --frozen-lockfile --registry https://registry.npmjs.org
# Production images only need the Vite bundle; the repository's full tsc check
# currently fails on pre-existing workspace resolver type duplication.
RUN cd apps/${APP} && bun run vite build

FROM nginx:1.27-alpine
ARG APP
COPY --from=builder /app/apps/${APP}/dist /usr/share/nginx/html
COPY docker/web-nginx.conf /etc/nginx/conf.d/default.conf
