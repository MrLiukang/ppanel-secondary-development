FROM oven/bun:1.3.1

WORKDIR /app

COPY package.json bun.lock bunfig.toml turbo.json tsconfig.json biome.jsonc ./
COPY apps ./apps
COPY packages ./packages
COPY docs ./docs

RUN bun install --frozen-lockfile

EXPOSE 3001

CMD ["sh", "-lc", "cd apps/admin && bun run dev -- --host 0.0.0.0 --port 3001"]
