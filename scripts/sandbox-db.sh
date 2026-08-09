#!/usr/bin/env bash
#
# Builds a disposable PostgreSQL sandbox and runs the §9 matrix against it.
#
#   scripts/sandbox-db.sh          # create, migrate, run the matrix, stop
#   scripts/sandbox-db.sh keep     # ... and leave it running for poking at
#   scripts/sandbox-db.sh stop     # stop a cluster left by `keep`
#
# ---------------------------------------------------------------------------
# WHY A LOCAL CLUSTER AND NOT A SUPABASE BRANCH.
#
# Branching is Pro-plan only and this org is on Free. It turned out not to matter:
# the entire billing schema depends on exactly three Supabase-specific things —
# the role names `anon` / `authenticated` / `service_role`, and `auth.uid()`. The
# roles are two lines and `auth.uid()` is stubbed below to read a session GUC,
# which is what makes `desktop_get_entitlement()` testable without minting JWTs.
#
# The live project is untouched by construction: nothing here has a network route
# to it, and the matrix never leaves this cluster.
# ---------------------------------------------------------------------------
set -euo pipefail

SOCK=/tmp/kbsbx
PGDATA="$SOCK/pgdata"
PORT=55432
DB=keigo_sandbox
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS="$REPO/../Japanese"

export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"
command -v initdb >/dev/null || { echo "PostgreSQL 16 not found (brew install postgresql@16)"; exit 1; }

psqlq() { psql -h "$SOCK" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -q "$@"; }

stop() { pg_ctl -D "$PGDATA" stop >/dev/null 2>&1 || true; }

if [[ "${1:-}" == "stop" ]]; then stop; echo "sandbox stopped"; exit 0; fi

# The socket directory has to be short: a Unix socket path is capped at 103 bytes
# and the scratchpad path alone is longer than that.
mkdir -p "$SOCK"
stop
rm -rf "$PGDATA"
initdb -D "$PGDATA" -U postgres --auth=trust >/dev/null
pg_ctl -D "$PGDATA" -o "-p $PORT -k $SOCK -c listen_addresses=''" -l "$SOCK/pg.log" start >/dev/null
sleep 2

psql -h "$SOCK" -p "$PORT" -U postgres -d postgres -tAc "create database $DB;" >/dev/null

psqlq -d "$DB" <<'SQL'
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create schema if not exists auth;

-- In production this reads the JWT claim. Here it reads a session GUC, so the
-- matrix can *be* a user and exercise the one entry point that derives its caller
-- from auth.uid() rather than from an argument (§7's IDOR rule).
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('sandbox.uid', true), '')::uuid
$$;
SQL

for f in "$REPO/supabase/migrations/20260807120000_desktop_schema.sql" \
         "$IOS/supabase/migrations/20260808120000_desktop_billing.sql" \
         "$IOS/supabase/migrations/20260808140000_desktop_billing_entry_points.sql" \
         "$IOS/supabase/migrations/20260808160000_desktop_entitlement_cancels_at.sql"; do
  printf '  %-50s' "$(basename "$f")"
  psqlq -d "$DB" -f "$f" >/dev/null && echo "applied"
done

echo
psql -h "$SOCK" -p "$PORT" -U postgres -d "$DB" -f "$REPO/scripts/billing-matrix.sql"

if [[ "${1:-}" != "keep" ]]; then
  stop
  echo
  echo "sandbox stopped. \`scripts/sandbox-db.sh keep\` leaves it up on port $PORT."
fi
