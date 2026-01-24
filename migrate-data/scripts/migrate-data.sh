#!/bin/bash
# Script tự động migrate data từ Oracle sang PostgreSQL

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_DIR phải là parent của migrate-data, không phải migrate-data chính nó
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_DIR="$PROJECT_DIR/ora2pg/config"
OUTPUT_DIR="$PROJECT_DIR/migrate-data/output"
LOGS_DIR="$PROJECT_DIR/migrate-data/logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOGS_DIR/migration-$TIMESTAMP.log"

# Create directories if not exist
mkdir -p "$OUTPUT_DIR"
mkdir -p "$LOGS_DIR"

# Get network name
NETWORK_NAME=$(docker network ls | grep -oP 'migrate-oracle-to-postgre[^ ]*' | head -1)
if [ -z "$NETWORK_NAME" ]; then
    NETWORK_NAME="migrate-oracle-to-postgre_default"
fi

echo "=========================================="
echo "Oracle to PostgreSQL Data Migration"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Network: $NETWORK_NAME"
echo "  Config: $CONFIG_DIR/ora2pg.conf"
echo "  Output: $OUTPUT_DIR"
echo "  Log: $LOG_FILE"
echo ""

# Step 1: Check containers
echo -e "${YELLOW}[1/5]${NC} Checking containers..."
if ! docker ps | grep -q "oracle-db"; then
    echo -e "${RED}ERROR: oracle-db container is not running!${NC}"
    exit 1
fi
if ! docker ps | grep -q "postgres-db"; then
    echo -e "${RED}ERROR: postgres-db container is not running!${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Containers are running${NC}"
echo ""

# Step 2: Test connections
echo -e "${YELLOW}[2/5]${NC} Testing connections..."
if ! "$SCRIPT_DIR/test-connections.sh" >> "$LOG_FILE" 2>&1; then
    echo -e "${RED}Connection test failed! Check log: $LOG_FILE${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Connections OK${NC}"
echo ""

# Step 3: Disable triggers and foreign keys in PostgreSQL
echo -e "${YELLOW}[3/5]${NC} Disabling triggers and foreign keys in PostgreSQL..."
DISABLE_SQL="
SET session_replication_role = 'replica';
DO \$\$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'TRUYENNHIEM_NEW') LOOP
        EXECUTE 'ALTER TABLE ' || quote_ident('TRUYENNHIEM_NEW') || '.' || quote_ident(r.tablename) || ' DISABLE TRIGGER ALL';
    END LOOP;
END \$\$;
"

if docker exec -i postgres-db psql -U postgres -d db_postgres <<< "$DISABLE_SQL" >> "$LOG_FILE" 2>&1; then
    echo -e "${GREEN}✅ Triggers and foreign keys disabled${NC}"
else
    echo -e "${YELLOW}⚠️  Failed to disable triggers (may not exist)${NC}"
fi
echo ""

# Step 4: Export and import data using Ora2Pg
echo -e "${YELLOW}[4/5]${NC} Exporting data from Oracle and importing to PostgreSQL..."
echo "This may take a while depending on data size..."
echo ""

EXPORT_LOG="$LOGS_DIR/export-$TIMESTAMP.log"
IMPORT_LOG="$LOGS_DIR/import-$TIMESTAMP.log"

# Run Ora2Pg migration
# Đảm bảo đường dẫn là absolute path
CONFIG_DIR_ABS=$(cd "$CONFIG_DIR" && pwd)
OUTPUT_DIR_ABS=$(cd "$OUTPUT_DIR" && pwd)

echo "Config directory: $CONFIG_DIR_ABS"
echo "Output directory: $OUTPUT_DIR_ABS"

if docker run --rm --network "$NETWORK_NAME" \
    -e ORACLE_HOME=/usr/lib/oracle/19.26/client64 \
    -e LD_LIBRARY_PATH=/usr/lib/oracle/19.26/client64/lib \
    -e TNS_ADMIN=/config \
    -v "$CONFIG_DIR_ABS:/config:ro" \
    -v "$OUTPUT_DIR_ABS:/data" \
    -v "$LOGS_DIR:/logs" \
    georgmoser/ora2pg:latest \
    bash -c "unset NLS_LANG; ora2pg -c /config/ora2pg.conf --debug" 2>&1 | tee "$EXPORT_LOG"; then
    
    echo ""
    echo -e "${GREEN}✅ Data export completed${NC}"
    
    # Import data files
    echo "Importing data files to PostgreSQL..."
    
    # Find all SQL files in output directory
    SQL_FILES=$(find "$OUTPUT_DIR" -name "*.sql" -type f | sort)
    
    if [ -z "$SQL_FILES" ]; then
        echo -e "${YELLOW}⚠️  No SQL files found in $OUTPUT_DIR${NC}"
        echo "   Check if Ora2Pg generated files in COPY format (.csv or .dat)"
    else
        IMPORTED=0
        FAILED=0
        
        for SQL_FILE in $SQL_FILES; do
            FILENAME=$(basename "$SQL_FILE")
            echo "  Importing $FILENAME..."
            
            if docker exec -i postgres-db psql -U postgres -d db_postgres \
                -v ON_ERROR_STOP=1 \
                < "$SQL_FILE" >> "$IMPORT_LOG" 2>&1; then
                echo -e "    ${GREEN}✅ $FILENAME imported${NC}"
                ((IMPORTED++))
            else
                echo -e "    ${RED}❌ $FILENAME failed${NC}"
                ((FAILED++))
            fi
        done
        
        echo ""
        echo "Import summary:"
        echo "  ✅ Imported: $IMPORTED files"
        if [ $FAILED -gt 0 ]; then
            echo -e "  ${RED}❌ Failed: $FAILED files${NC}"
            echo "  Check log: $IMPORT_LOG"
        fi
    fi
else
    echo -e "${RED}❌ Data export failed!${NC}"
    echo "Check log: $EXPORT_LOG"
    exit 1
fi
echo ""

# Step 5: Enable triggers and foreign keys
echo -e "${YELLOW}[5/5]${NC} Enabling triggers and foreign keys in PostgreSQL..."
ENABLE_SQL="
SET session_replication_role = 'origin';
DO \$\$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'TRUYENNHIEM_NEW') LOOP
        EXECUTE 'ALTER TABLE ' || quote_ident('TRUYENNHIEM_NEW') || '.' || quote_ident(r.tablename) || ' ENABLE TRIGGER ALL';
    END LOOP;
END \$\$;
"

if docker exec -i postgres-db psql -U postgres -d db_postgres <<< "$ENABLE_SQL" >> "$LOG_FILE" 2>&1; then
    echo -e "${GREEN}✅ Triggers and foreign keys enabled${NC}"
else
    echo -e "${YELLOW}⚠️  Failed to enable triggers${NC}"
fi
echo ""

echo "=========================================="
echo -e "${GREEN}Migration completed!${NC}"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Validate data: ./scripts/validate-data.sh"
echo "  2. Check logs: $LOG_FILE"
echo "  3. Check export log: $EXPORT_LOG"
echo "  4. Check import log: $IMPORT_LOG"
echo ""
