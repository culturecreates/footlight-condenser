#!/usr/bin/env bash
# Repeatable, local PostgreSQL 17 test setup for PR #14.
# This script NEVER touches the development Danse Danse QA database.
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

DB='footlight_condenser_keyed_qa_test'
SOCKET='/var/run/postgresql'
PORT='5433'
BRANCH='feat/keyed-resource-list-alignment'
MODE="${1:-run}"

case "$MODE" in
  run|--reset|--status) ;;
  *) echo 'Usage: bash script/run_keyed_qa_tests.sh [--reset|--status]' >&2; exit 2 ;;
esac

[[ "$(git branch --show-current)" == "$BRANCH" ]] || { echo "Refusing: must be on $BRANCH" >&2; exit 2; }
[[ -z "${DATABASE_URL:-}" && -z "${TEST_DATABASE_URL:-}" ]] || { echo 'Refusing: DATABASE_URL/TEST_DATABASE_URL is set.' >&2; exit 2; }
[[ -z "${PGHOST:-}" || "${PGHOST}" == "$SOCKET" ]] || { echo 'Refusing: a non-local PGHOST is set.' >&2; exit 2; }
[[ -z "${PGPORT:-}" || "${PGPORT}" == "$PORT" ]] || { echo 'Refusing: PGPORT is set to a different port.' >&2; exit 2; }
[[ -z "${PGUSER:-}" || "${PGUSER}" == "$(id -un)" ]] || { echo 'Refusing: unexpected PGUSER.' >&2; exit 2; }
[[ -z "${RAILS_ENV:-}" || "${RAILS_ENV}" == 'test' ]] || { echo 'Refusing: RAILS_ENV must be test.' >&2; exit 2; }
[[ -f config/database.yml && -f db/schema.rb ]] || { echo 'Missing Rails database/schema config.' >&2; exit 2; }

for executable in git psql; do command -v "$executable" >/dev/null || { echo "Missing $executable" >&2; exit 2; }; done
OWNER="$(id -un)"
[[ "$OWNER" =~ ^[a-zA-Z_][a-zA-Z_0-9]*$ ]] || { echo "Invalid local DB role: $OWNER" >&2; exit 2; }

psql_test() { env -u PGDATABASE -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -h "$SOCKET" -p "$PORT" -U "$OWNER" -d "$DB" "$@"; }
psql_admin() { sudo -u postgres psql -X -v ON_ERROR_STOP=1 -h "$SOCKET" -p "$PORT" -d postgres "$@"; }
psql_admin_test() { sudo -u postgres psql -X -v ON_ERROR_STOP=1 -h "$SOCKET" -p "$PORT" -d "$DB" "$@"; }
rails() {
  env -u DATABASE_URL -u TEST_DATABASE_URL -u PGDATABASE -u PGOPTIONS -u FOOTLIGHT_CONDENSER_DB_TEST \
    RAILS_ENV=test DISABLE_SPRING=1 PGHOST="$SOCKET" PGPORT="$PORT" \
    'FOOTLIGHT-CONDENSER-DB_TEST=footlight_condenser_keyed_qa_test' bin/rails "$@"
}

exists_db() {
  env -u PGDATABASE -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -h "$SOCKET" -p "$PORT" -U "$OWNER" \
    -d postgres -At -c "SELECT 1 FROM pg_database WHERE datname='$DB';" | grep -qx 1
}
ready_db() {
  exists_db || return 1
  [[ "$(psql_test -At -c "SELECT CASE WHEN to_regclass('public.websites') IS NOT NULL AND to_regclass('public.schema_migrations') IS NOT NULL AND EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_stat_statements') THEN 'ready' ELSE 'missing' END;")" == 'ready' ]] || return 1
  [[ "$(psql_test -At -c "SELECT version FROM schema_migrations WHERE version='20261127000100';")" == '20261127000100' ]] || return 1
  [[ "$(psql_test -At -c "SELECT value FROM ar_internal_metadata WHERE key='environment';")" == 'test' ]] || return 1
}

if [[ "$MODE" == '--status' ]]; then
  if ready_db; then echo "READY: $DB (PG $PORT)"; else echo "NOT READY: $DB (PG $PORT); run with --reset"; fi
  exit 0
fi

if [[ "$MODE" == '--reset' ]]; then
  command -v sudo >/dev/null || { echo 'Missing sudo; required only for test database reset.' >&2; exit 2; }
  echo "Resetting ONLY disposable local database $DB on PostgreSQL $PORT. All its contents will be deleted."
  # Use explicit --reset flag as authorization; no FORCE / terminate_backend.
  psql_admin -c "DROP DATABASE IF EXISTS \"$DB\";"
  psql_admin -c "CREATE DATABASE \"$DB\" OWNER \"$OWNER\" TEMPLATE template0;"
  psql_admin_test -c 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;'
  rails db:schema:load
fi

if ! ready_db; then
  echo "Test DB $DB is not initialized at expected schema. Re-run with --reset (destructive to test DB only)." >&2
  exit 1
fi

printf '\nRunning focused tests against %s only...\n' "$DB"
rails test \
  test/services/resource_lists/danse_danse_keyed_preview_test.rb \
  test/controllers/websites_controller_test.rb \
  test/services/resource_lists/keyed_calendar_alignment_test.rb \
  test/services/resource_lists/keyed_calendar_extractor_test.rb
