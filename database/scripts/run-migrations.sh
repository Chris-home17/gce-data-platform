#!/usr/bin/env bash
# =============================================================================
# run-migrations.sh
# Applies all pending database migrations in numerical order.
# =============================================================================
# Usage:
#   ./database/scripts/run-migrations.sh [--server <server>] [--database <db>]
#
# Environment variables (override with flags):
#   DB_SERVER    Fabric SQL / Azure SQL server FQDN
#   DB_NAME      Database name
#   DB_USER      SQL login (or use --use-msi for managed identity)
#   DB_PASSWORD  SQL password (omit if using MSI)
#
# Dependencies: sqlcmd (installed via mssql-tools or azure-cli)
# =============================================================================

set -euo pipefail

MIGRATIONS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../migrations" && pwd)"
SERVER="${DB_SERVER:-}"
DATABASE="${DB_NAME:-}"
USER="${DB_USER:-}"
PASSWORD="${DB_PASSWORD:-}"
USE_MSI=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --server)   SERVER="$2";   shift 2 ;;
        --database) DATABASE="$2"; shift 2 ;;
        --user)     USER="$2";     shift 2 ;;
        --password) PASSWORD="$2"; shift 2 ;;
        --use-msi)  USE_MSI=1;     shift   ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$SERVER" || -z "$DATABASE" ]]; then
    echo "ERROR: --server and --database are required (or set DB_SERVER / DB_NAME)"
    exit 1
fi

echo "=== GCE Data Platform — Migration Runner ==="
echo "  Server   : $SERVER"
echo "  Database : $DATABASE"
echo "  Mode     : $([ $USE_MSI -eq 1 ] && echo 'Managed Identity' || echo 'SQL Auth')"
echo ""

# Build sqlcmd auth flags
if [[ $USE_MSI -eq 1 ]]; then
    AUTH_FLAGS="-G"
else
    AUTH_FLAGS="-U $USER -P $PASSWORD"
fi

# Find and sort migration files
mapfile -t FILES < <(find "$MIGRATIONS_DIR" -name "*.sql" | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No migration files found in $MIGRATIONS_DIR"
    exit 0
fi

for FILE in "${FILES[@]}"; do
    FILENAME=$(basename "$FILE")
    echo "  Applying: $FILENAME"
    sqlcmd -S "$SERVER" -d "$DATABASE" $AUTH_FLAGS -i "$FILE" -b -V 16
    if [[ $? -ne 0 ]]; then
        echo "  FAILED: $FILENAME — stopping."
        exit 1
    fi
    echo "  OK: $FILENAME"
done

echo ""
echo "=== All migrations applied successfully ==="
