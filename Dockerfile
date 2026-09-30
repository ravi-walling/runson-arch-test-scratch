# Standalone Dockerfile for Mastra Studio — see ./README.md and
# docs/ops-agents/mastra-spike.md (T5 "Studio" section, T4's Railway-domain
# incident note). Studio is served by the standalone `mastra` npm CLI, not
# `@mastra/nestjs` (T5 confirmed: no "studio"/"playground" hits in
# @mastra/nestjs's or @mastra/core's shipped .d.ts/README) — it is not part
# of this monorepo's Nx/pnpm build, so this Dockerfile is deliberately much
# simpler than the other apps/*/Dockerfiles: one `npm install` of a pinned
# CLI package, no workspace source copied in, no build step.
#
# No package.json is committed in this directory on purpose: pnpm-workspace.yaml's
# `apps/*` glob would otherwise pull an `apps/ops-mastra-studio/package.json`
# into the root pnpm-lock.yaml as a workspace member for zero benefit — this
# image's only dependency is one CLI tool, unrelated to the monorepo's own
# dependency graph. `npm` (not `pnpm`) installs it inside the image instead.
#
# Version pins (exact, matching docs/ops-agents/mastra-spike.md T1's
# `--save-exact` convention for every other @mastra/* package in this repo):
#   mastra@1.30.0        — the standalone CLI that ships Studio.
#   @mastra/core@1.67.0  — this repo's own pinned core version (T1); `mastra`
#                           needs it as a sibling to resolve its API-client
#                           types against. T5 already documented the version
#                           gap between these two (CLI at 1.30.0, core at
#                           1.67.0) as a known, non-blocking risk — do not
#                           "fix" the gap by floating either version here.
# Next bump: see the upgrade-sync procedure note appended to
# docs/ops-agents/mastra-spike.md's T1 section — re-check both pins together.
#
# Node version pinned to match this repo's package.json `volta.node` so
# container behavior matches local dev. Renovate does not manage this pin
# (this Dockerfile sits outside the Nx graph) — bump it by hand.
FROM node:22.23.2-alpine

# Fail-fast shell, matching every other Dockerfile in this repo.
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

RUN apk add --no-cache dumb-init

RUN addgroup -g 1001 -S mastra && adduser -S mastra -u 1001

WORKDIR /app

# --no-save: no package.json/lockfile to write into (none is committed, see
# above). --omit=dev: neither package ships anything this image needs beyond
# its own runtime deps.
RUN npm install --no-save --omit=dev mastra@1.30.0 @mastra/core@1.67.0 \
    && npm cache clean --force

RUN chown -R mastra:mastra /app
USER mastra

ENTRYPOINT ["dumb-init", "--"]

# The Mastra instance to point Studio at is resolved at CONTAINER START, not
# baked into the image at build time — redeploying against a different
# ops-workers instance (e.g. local drill vs. staging) never needs a rebuild,
# only different env vars at `docker run` / in Railway's service variables.
#
# Defaults point at ops-workers' EXISTING public staging hostname
# (docs/ops-agents/mastra-spike.md T4's "Incident: an unintended Railway
# public domain" — reused as-is, never re-created; see this app's README for
# a live reachability finding recorded at scaffold time). `PORT` is
# Railway's own dynamic-port-assignment convention for the container's own
# listen port; `mastra studio` needs no separate `--host` flag to accept
# non-loopback connections — verified locally (this CLI version's own
# `--help` has no such flag, and it binds all interfaces, `*:<port>`, by
# default) — see the README for how that was checked.
CMD ["sh", "-c", "exec node_modules/.bin/mastra studio --port \"${PORT:-3000}\" --server-host \"${MASTRA_STUDIO_SERVER_HOST:-ops-workers-staging.up.railway.app}\" --server-port \"${MASTRA_STUDIO_SERVER_PORT:-443}\" --server-protocol \"${MASTRA_STUDIO_SERVER_PROTOCOL:-https}\" --server-api-prefix \"${MASTRA_STUDIO_SERVER_API_PREFIX:-/mastra}\""]
