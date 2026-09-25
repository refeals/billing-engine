#!/usr/bin/env bash
# Starts the API for the end-to-end suite: test environment, its own SQLite file, simulator
# on, CORS open to the preview server. Uses mise when it is installed (local machines);
# CI puts Ruby on the PATH directly.
set -euo pipefail
cd "$(dirname "$0")/../../api"

export RAILS_ENV=test
export TEST_DATABASE=storage/e2e.sqlite3
export SIMULATOR_ENABLED=true
export WEB_ORIGIN=http://localhost:4174

run() {
  if command -v mise >/dev/null 2>&1; then mise exec -- "$@"; else "$@"; fi
}

run bin/rails db:prepare
run bin/rails demo:ensure_user
# A server killed mid-run leaves its pid file behind, and Rails refuses to start over it.
rm -f tmp/pids/e2e.pid
exec_cmd=(bin/rails server -p 3100 -P tmp/pids/e2e.pid)
if command -v mise >/dev/null 2>&1; then exec mise exec -- "${exec_cmd[@]}"; else exec "${exec_cmd[@]}"; fi
