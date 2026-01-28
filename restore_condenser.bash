#!/bin/bash

# Usage: sudo -u postgres bash restore_condenser.bash latest.dump condenser_upgrade [db_owner]
# Default db_owner is "educa"

set -e

DUMP_FILE="$1"
DB_NAME="$2"
DB_OWNER="${3:-educa}"

if [[ -z "$DUMP_FILE" || -z "$DB_NAME" ]]; then
  echo "Usage: sudo -u postgres bash restore_condenser.bash <dump_file> <db_name> [db_owner]"
  exit 1
fi

echo ">> Ensuring role '$DB_OWNER' exists"
psql -tc "SELECT 1 FROM pg_roles WHERE rolname = '$DB_OWNER'" | grep -q 1 || psql -c "CREATE ROLE $DB_OWNER WITH LOGIN CREATEDB PASSWORD '$DB_OWNER';"

echo ">> Dropping existing database (if any): $DB_NAME"
dropdb --if-exists "$DB_NAME"

echo ">> Creating new database: $DB_NAME owned by $DB_OWNER"
createdb --owner="$DB_OWNER" "$DB_NAME"

echo ">> Creating extension pg_stat_statements (if needed)"
psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"

echo ">> Creating schema heroku_ext (if needed)"
psql -d "$DB_NAME" -c "CREATE SCHEMA IF NOT EXISTS heroku_ext;"

echo ">> Restoring database from: $DUMP_FILE (as role: $DB_OWNER)"
pg_restore --verbose --clean --no-owner --role="$DB_OWNER" --dbname="$DB_NAME" "$DUMP_FILE" | tee restore.log

echo ">> Checking for permission/ownership issues..."
grep -Ei "owner|denied|skipping|execute" restore.log || echo "✅ No permission issues found."

echo ">> Done. Verifying tables:"
psql -d "$DB_NAME" -c "\dt"

echo ">> ✅ Restore complete. Database '$DB_NAME' is owned by '$DB_OWNER'."
