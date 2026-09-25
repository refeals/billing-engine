# 15 — Deploy with Dokploy

## Goal

Publish the project as a live demo: the code on GitHub, both apps running on a VPS managed by
[Dokploy](https://dokploy.com), each on its own HTTPS domain, redeployed on every push to
`main`. A reviewer opens a URL and lands on the seeded dashboard.

## Depends on

- `14-documentation-and-release.md` (tagged `v1.0.0`, CI green).

## Scope

**In**
- Container images for the API and the web app (`Dockerfile`s, entrypoint, `.dockerignore`).
- The production settings the demo needs.
- Dokploy setup, step by step: two applications, domains, environment, persistent volume,
  automatic deploys.
- An optional nightly demo reset.
- README: "Live demo" link and a pointer to this file.

**Out**
- Authentication, rate limiting, multiple instances, an external database. The live app is
  a demo with disposable data (see [Risks](#risks-of-a-public-demo)).

## Decisions

1. **Two Dokploy Applications from one repository**, not a Docker Compose stack. The repo is a
   monorepo (`api/`, `web/`); Dokploy builds each application from its own *Build Path*.
   Each application gets its own domain, logs, environment and redeploy, with nothing to
   wire by hand. Compose would work too, but adds a file that only exists for deployment
   and puts two unrelated build contexts in one unit.
2. **Two domains**: `billing.rafaelsiqueira.dev` (web) and `billing-api.rafaelsiqueira.dev`
   (API). The web app calls the API cross-origin, exactly as in development, so CORS
   (`WEB_ORIGIN`) and `VITE_API_URL` are the only coupling. Traefik (bundled with Dokploy)
   terminates HTTPS with Let's Encrypt certificates.
3. **SQLite on a persistent volume.** One API container, one Puma process, the database files
   in `/rails/storage` mounted as a Dokploy volume. No database server to run or back up:
   the data is a demo, rebuilt by the seeds whenever needed.
4. **The simulator stays on in production** (`SIMULATOR_ENABLED=true`). Without it there is
   no clock, no Scenario Lab and no fake provider, so no demo. The consequences are listed
   under [Risks](#risks-of-a-public-demo).
5. **The first boot seeds the demo.** The entrypoint runs `bin/rails db:prepare`: on an empty
   volume it creates both databases from `db/structure.sql` and `db/queue_schema.rb`, then
   runs `db/seeds.rb` (about 15 seconds of simulated history); on later boots it only
   applies pending migrations. Redeploys keep the data.
6. **The web app is static.** Vite builds it with `VITE_API_URL` baked in at build time,
   and nginx serves it with a fallback to `index.html` for client-side routes. Changing the
   API URL means rebuilding, not restarting.

## Files to add

### `api/Dockerfile`

Multi-stage, based on the Ruby version in `api/.ruby-version`:

```dockerfile
# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.4.11
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# sqlite3 CLI: Rails loads db/structure.sql through it (the append-only triggers live there).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libyaml-0-2 sqlite3 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY . .
RUN bundle exec bootsnap precompile app/ lib/

FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p storage log tmp && \
    chown -R rails:rails storage log tmp
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
```

### `api/bin/docker-entrypoint` (executable)

```sh
#!/bin/bash -e

# jemalloc keeps Ruby's memory flat on a small VPS.
if [ -z "${LD_PRELOAD+x}" ]; then
  LD_PRELOAD=$(find /usr/lib -name libjemalloc.so.2 -print -quit)
  export LD_PRELOAD
fi

# Creates and seeds the databases on an empty volume, migrates on later deploys.
if [ "$1" == "./bin/rails" ] && [ "$2" == "server" ]; then
  ./bin/rails db:prepare
fi

exec "${@}"
```

### `api/.dockerignore`

```
.git
.env*
config/master.key
log/*
tmp/*
storage/*
spec/
vendor/bundle
```

### `web/Dockerfile`

```dockerfile
# syntax=docker/dockerfile:1
FROM docker.io/library/node:24-alpine AS build

WORKDIR /app
RUN corepack enable

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
```

### `web/nginx.conf`

```nginx
server {
  listen 80;
  root /usr/share/nginx/html;

  # Client-side routes (/subscriptions/12/history) are served by the SPA.
  location / {
    try_files $uri $uri/ /index.html;
  }

  # Vite fingerprints assets, so they can be cached forever; index.html never is.
  location /assets/ {
    add_header Cache-Control "public, max-age=31536000, immutable";
  }
  location = /index.html {
    add_header Cache-Control "no-cache";
  }
}
```

### `web/.dockerignore`

```
node_modules
dist
.env*
.eslintcache
```

### Production settings

- `api/config/environments/production.rb`: `config.assume_ssl = true` (Traefik terminates
  TLS and forwards plain HTTP; Rails should still treat requests as HTTPS). Leave
  `force_ssl` off: Traefik already redirects HTTP to HTTPS, and `/up` must answer plain HTTP
  inside the Docker network.
- No other change. Active Job's queue database (`production_queue.sqlite3`) is created by
  `db:prepare` next to the main database, on the same volume.

## Before pushing to GitHub

- `api/config/master.key` must **not** be in the repository. It is ignored by
  `api/.gitignore`; confirm with `git ls-files api/config/master.key` (no output). The
  production app doesn't read credentials at all; it only needs `SECRET_KEY_BASE`.
- `.env` files are ignored in both apps; only `web/.env.example` is committed.
- The screenshots and the seed data are fictional; nothing personal is published.

## Dokploy setup, step by step

### 1. DNS

Point two records at the VPS's public IP:

| Type | Name | Value |
|---|---|---|
| A | `billing.rafaelsiqueira.dev` | VPS IP |
| A | `billing-api.rafaelsiqueira.dev` | VPS IP |

Wait until `dig +short billing-api.rafaelsiqueira.dev` returns the IP; Let's Encrypt validation
fails until it does.

**With Cloudflare DNS, keep every name one level deep.** Cloudflare's free certificate covers
`rafaelsiqueira.dev` and `*.rafaelsiqueira.dev` only, so a proxied (orange) two-level name such
as `api.billing.rafaelsiqueira.dev` fails the TLS handshake at Cloudflare's edge
(`ERR_SSL_VERSION_OR_CIPHER_MISMATCH`) before reaching the VPS; that is why the API lives at
`billing-api`. Proxied records need SSL mode **Full (strict)** (Traefik has a valid Let's
Encrypt certificate behind it); "Flexible" loops with Traefik's HTTP→HTTPS redirect. Setting a
record to "DNS only" (grey cloud) also works, with Traefik answering directly.

### 2. Connect GitHub

Dokploy → **Settings → Git → GitHub** → create the GitHub App and install it on the
repository (or on the account, limited to this repository). This lets Dokploy clone private
repositories and receive push events for automatic deploys.

### 3. Create a project

**Projects → Create Project**: `billing-engine`. Both applications live inside it.

### 4. The API application

**Create Service → Application**, name `billing-api`.

- **General → Provider**: GitHub, repository `billing-engine`, branch `main`,
  **Build Path** `/api`.
- **Build Type**: Dockerfile, **Docker File** `Dockerfile` (relative to the build path).
- **Environment**:

  ```
  RAILS_ENV=production
  SECRET_KEY_BASE=<output of: cd api && bin/rails secret>
  SIMULATOR_ENABLED=true
  WEB_ORIGIN=https://billing.rafaelsiqueira.dev
  RAILS_LOG_LEVEL=info
  ```

  `WEB_ORIGIN` must match the web domain exactly (scheme included, no trailing slash), or
  the browser blocks every request with a CORS error.
- **Advanced → Mounts → Add Mount**: type **Volume**, name `billing-api-storage`,
  mount path `/rails/storage`. Without it every deploy starts from an empty database.
- **Domains → Add Domain**: host `billing-api.rafaelsiqueira.dev`, path `/`, **container port
  `3000`**, HTTPS on, certificate **Let's Encrypt**.
- **Deploy**. The first boot runs the seeds; the logs show `db:prepare`, then Puma
  listening on port 3000.

Check: `curl https://billing-api.rafaelsiqueira.dev/up` answers 200 and
`curl https://billing-api.rafaelsiqueira.dev/api/v1/dashboard/summary` returns the seeded figures
(20 customers' subscriptions, zero open discrepancies).

### 5. The web application

**Create Service → Application**, name `billing-web`.

- **Provider**: same repository and branch, **Build Path** `/web`.
- **Build Type**: Dockerfile, **Docker File** `Dockerfile`.
- **Environment → Build-time arguments** (not runtime variables: Vite reads it while
  building):

  ```
  VITE_API_URL=https://billing-api.rafaelsiqueira.dev/api/v1
  ```

- **Domains → Add Domain**: host `billing.rafaelsiqueira.dev`, path `/`, **container port `80`**,
  HTTPS on, Let's Encrypt.
- **Deploy**, then open `https://billing.rafaelsiqueira.dev`: the dashboard shows
  "Figures as of Mar 16, 2026".

### 6. Automatic deploys

With the GitHub provider, **Autodeploy** (on by default in each application's General tab)
redeploys on every push to `main`. Two refinements, both optional:

- **Watch Paths** (each application's General tab): `api/**` for `billing-api` and `web/**`
  for `billing-web`, so a push that only changes the web app doesn't rebuild the API. Docs
  changes then redeploy nothing.
- **Deploy only after CI passes**: turn Autodeploy off, copy each application's **Deploy
  Webhook** URL (Deployments tab) into GitHub repository secrets, and add a job to
  `.github/workflows/ci.yml` that runs after `api` and `web` succeed on `main` and calls
  `curl -fsS -X POST "$DOKPLOY_API_WEBHOOK"` (and the web one).

### 7. Nightly demo reset (optional)

Visitors share one simulated clock and one dataset, and the Scenario Lab moves both. To bring
the demo back to its seeded state every night, add a scheduled job in Dokploy for
`billing-api` (**Schedules**, where the installed version has them) with cron `0 4 * * *`
and command:

```sh
bin/rails runner 'Demo::Reset.call'
```

Where schedules aren't available, the same from the VPS's crontab:

```sh
0 4 * * * docker exec $(docker ps -q -f name=billing-api) bin/rails runner 'Demo::Reset.call'
```

## Environment reference

| Variable | App | When | Value |
|---|---|---|---|
| `RAILS_ENV` | api | runtime | `production` (already set by the image) |
| `SECRET_KEY_BASE` | api | runtime | `bin/rails secret`; keep it out of the repository |
| `SIMULATOR_ENABLED` | api | runtime | `true`: the demo needs the clock, the Scenario Lab and the fake provider |
| `WEB_ORIGIN` | api | runtime | `https://billing.rafaelsiqueira.dev` |
| `RAILS_LOG_LEVEL` | api | runtime | `info` |
| `VITE_API_URL` | web | **build** | `https://billing-api.rafaelsiqueira.dev/api/v1` |

## Risks of a public demo

Accepted for a portfolio demo, and stated in the README next to the live link:

- **Public demo credentials.** Since plan 16 the app has a login, but its only user's
  credentials are printed on the login screen, so anyone can still create customers, move
  the clock, run scenarios or reset the data. Data is fictional and disposable, and the
  nightly reset restores it (it keeps the demo user and open sessions).
- **The webhook endpoint accepts unsigned events** while the simulator is on (by design, so
  the fake provider can deliver). Someone could post fabricated events; the worst outcome is
  a confusing demo until the next reset. Real signature verification is already listed as a
  future improvement.
- **One shared clock.** Two visitors running scenarios at once see each other's time jumps.
  The Scenario Lab says so on screen.
- **SQLite and one process.** Fine for demo traffic. Scaling out would need a database
  server first; not a goal here.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Web loads, every request fails with a CORS error | `WEB_ORIGIN` doesn't match the web domain exactly, or the API wasn't redeployed after changing it |
| Web calls `localhost:3001` | `VITE_API_URL` was set as a runtime variable instead of a build-time argument, or the web app wasn't rebuilt |
| Deep link such as `/subscriptions/3` returns 404 | `nginx.conf` wasn't copied (missing `try_files … /index.html`) |
| API crashes with `Missing secret_key_base` | `SECRET_KEY_BASE` not set |
| `/api/v1/simulator/...` returns 404 | `SIMULATOR_ENABLED` isn't exactly `true` |
| Data disappears after each deploy | The volume isn't mounted at `/rails/storage` |
| First deploy marked unhealthy | The seeds take about 15 seconds on first boot; retry, or raise the health check's start period |
| `db:prepare` fails with `sqlite3: not found` | The image lost the `sqlite3` package (needed to load `structure.sql`) |
| Certificate not issued | DNS not propagated yet, or ports 80/443 closed on the VPS firewall |
| `ERR_SSL_VERSION_OR_CIPHER_MISMATCH` / `sslv3 alert handshake failure`, `server: cloudflare` | The record is proxied by Cloudflare and the name is two levels deep (`api.billing.…`); use a one-level name or "DNS only" |

## Verification

1. Local: `docker build -t billing-api api` and
   `docker build --build-arg VITE_API_URL=http://localhost:3000/api/v1 -t billing-web web`;
   run the API with a volume and `SECRET_KEY_BASE`, `SIMULATOR_ENABLED=true`,
   `WEB_ORIGIN=http://localhost:8080`; run the web image on port 8080; the dashboard shows
   the seeded demo, and every Scenario Lab scenario passes.
2. Restart the API container: the data is still there (volume) and no seed runs again.
3. On Dokploy: both domains serve HTTPS; `/up` answers 200; a push to `main` redeploys.
4. Every scenario passes against the live API:
   `curl -X POST https://billing-api.rafaelsiqueira.dev/api/v1/simulator/scenarios/<key>/run`.

## Documentation

- README: a "Live demo" link at the top, with one line on the shared clock and the nightly
  reset; a "Deploy" subsection under Quick start pointing to this file.
- Future improvements: remove "a hosted demo".

## Decisions taken during implementation

- **pnpm is pinned in the web image** (`corepack prepare pnpm@10.23.0`): `package.json` has
  no `packageManager` field, so corepack would otherwise fetch whatever pnpm is latest.
- **Tested locally with Docker** exactly as Dokploy runs it (volume at `/rails/storage`,
  the environment above, web built with `VITE_API_URL`): first boot seeded in about 10
  seconds (YJIT on), the dashboard showed MRR $895.17 and zero discrepancies, a deep link
  rendered through nginx, CORS answered for the web origin, all ten scenarios passed, and a
  container restart kept the data without reseeding. The nightly reset command took about 8
  seconds.
- The API image runs as uid 1000 and contains no `config/master.key`, `.env` or `spec/`.
- Remaining manual steps are Dokploy's (DNS, GitHub App, applications, domains, volume,
  environment). Once live, add the URL to the README and remove "a hosted demo" from the
  future improvements.

## Acceptance criteria

- A push to `main` puts the new version live without manual steps.
- A first-time visitor lands on the seeded dashboard over HTTPS, can run every scenario, and
  the data survives redeploys.
