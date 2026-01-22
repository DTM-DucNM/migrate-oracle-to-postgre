#!/bin/bash
# Script để validate data sau khi migration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCHEMA_NAME="TRUYENNHIEM_NEW"

echo "=========================================="
echo "Data Validation: Oracle vs PostgreSQL"
echo "=========================================="
echo ""

# Function to get table count from Oracle
get_oracle_count() {
    local table_name=$1
    docker exec oracle-db sqlplus -s system/123456@XEPDB1 <<EOF | grep -v "^$" | tail -1
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SELECT COUNT(*) FROM $SCHEMA_NAME.$table_name;
EXIT
EOF
}

# Function to get table count from PostgreSQL
get_postgres_count() {
    local table_name=$1
    docker exec postgres-db psql -U postgres -d db_postgres -t -c \
        "SELECT COUNT(*) FROM $SCHEMA_NAME.$table_name;" 2>/dev/null | tr -d ' '
}

# Get list of tables from Oracle
echo -e "${BLUE}[1/3]${NC} Getting list of tables from Oracle..."
ORACLE_TABLES=$(docker exec oracle-db sqlplus -s system/123456@XEPDB1 <<EOF | grep -v "^$" | grep -v "^-" | grep -v "rows selected" | grep -v "TABLE_NAME" | tr -d ' '
SET PAGESIZE 0
SET FEEDBACK OFF
SELECT table_name FROM all_tables WHERE owner = '$SCHEMA_NAME' ORDER BY table_name;
EXIT
EOF
)

if [ -z "$ORACLE_TABLES" ]; then
    echo -e "${RED}❌ No tables found in Oracle schema: $SCHEMA_NAME${NC}"
    exit 1
fi

TABLE_COUNT=$(echo "$ORACLE_TABLES" | wc -l)
echo -e "${GREEN}✅ Found $TABLE_COUNT tables in Oracle${NC}"
echo ""

# Get list of tables from PostgreSQL
echo -e "${BLUE}[2/3]${NC} Getting list of tables from PostgreSQL..."
POSTGRES_TABLES=$(docker exec postgres-db psql -U postgres -d db_postgres -t -c \
    "SELECT tablename FROM pg_tables WHERE schemaname = '$SCHEMA_NAME' ORDER BY tablename;" | tr -d ' ')

if [ -z "$POSTGRES_TABLES" ]; then
    echo -e "${RED}❌ No tables found in PostgreSQL schema: $SCHEMA_NAME${NC}"
    exit 1
fi

PG_TABLE_COUNT=$(echo "$POSTGRES_TABLES" | wc -l)
echo -e "${GREEN}✅ Found $PG_TABLE_COUNT tables in PostgreSQL${NC}"
echo ""

# Compare table counts
echo -e "${BLUE}[3/3]${NC} Comparing row counts..."
echo ""
printf "%-40s %15s %15s %10s\n" "TABLE_NAME" "ORACLE" "POSTGRES" "STATUS"
printf "%-40s %15s %15s %10s\n" "$(printf '=%.0s' {1..40})" "$(printf '=%.0s' {1..15})" "$(printf '=%.0s' {1..15})" "$(printf '=%.0s' {1..10})"

MATCHED=0
MISMATCHED=0
MISSING=0
ERRORS=0

for TABLE in $ORACLE_TABLES; do
    # Check if table exists in PostgreSQL
    if echo "$POSTGRES_TABLES" | grep -q "^${TABLE}$"; then
        # Get counts
        ORACLE_COUNT=$(get_oracle_count "$TABLE" 2>/dev/null || echo "ERROR")
        POSTGRES_COUNT=$(get_postgres_count "$TABLE" 2>/dev/null || echo "ERROR")
        
        if [ "$ORACLE_COUNT" = "ERROR" ] || [ "$POSTGRES_COUNT" = "ERROR" ]; then
            printf "%-40s %15s %15s %10s\n" "$TABLE" "$ORACLE_COUNT" "$POSTGRES_COUNT" "${RED}ERROR${NC}"
            ((ERRORS++))
        elif [ "$ORACLE_COUNT" = "$POSTGRES_COUNT" ]; then
            printf "%-40s %15s %15s %10s\n" "$TABLE" "$ORACLE_COUNT" "$POSTGRES_COUNT" "${GREEN}OK${NC}"
            ((MATCHED++))
        else
            printf "%-40s %15s %15s %10s\n" "$TABLE" "$ORACLE_COUNT" "$POSTGRES_COUNT" "${RED}MISMATCH${NC}"
            ((MISMATCHED++))
        fi
    else
        printf "%-40s %15s %15s %10s\n" "$TABLE" "N/A" "MISSING" "${RED}MISSING${NC}"
        ((MISSING++))
    fi
done

echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo -e "${GREEN}✅ Matched: $MATCHED tables${NC}"
if [ $MISMATCHED -gt 0 ]; then
    echo -e "${RED}❌ Mismatched: $MISMATCHED tables${NC}"
fi
if [ $MISSING -gt 0 ]; then
    echo -e "${RED}❌ Missing in PostgreSQL: $MISSING tables${NC}"
fi
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}❌ Errors: $ERRORS tables${NC}"
fi
echo ""

# Sample data comparison (optional)
if [ $MISMATCHED -gt 0 ] || [ $MISSING -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Some tables have issues. Check the details above.${NC}"
    echo ""
    echo "To investigate further:"
    echo "  1. Check migration logs in ora2pg/logs/"
    echo "  2. Compare sample data manually"
    echo "  3. Check for data type conversion issues"
fi

if [ $MATCHED -eq $TABLE_COUNT ] && [ $MISMATCHED -eq 0 ] && [ $MISSING -eq 0 ] && [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All tables validated successfully!${NC}"
fi

echo ""
