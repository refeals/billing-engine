# syntax=docker/dockerfile:1
FROM docker.io/library/node:24-alpine AS build

WORKDIR /app
# package.json has no packageManager field; pin the pnpm the lockfile was made with.
RUN corepack enable && corepack prepare pnpm@10.23.0 --activate

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .
# Baked into the bundle: changing it requires a rebuild.
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL
RUN pnpm build-only

FROM docker.io/library/nginx:1.29-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
