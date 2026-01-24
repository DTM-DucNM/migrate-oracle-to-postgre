#!/bin/bash
# Script để test kết nối Oracle và PostgreSQL từ Ora2Pg container

set -e

echo "=========================================="
echo "Testing Oracle and PostgreSQL Connections"
echo "=========================================="
echo ""

# Lấy network name từ docker-compose
NETWORK_NAME=$(docker network ls | grep -oP 'migrate-oracle-to-postgre[^ ]*' | head -1)
if [ -z "$NETWORK_NAME" ]; then
    NETWORK_NAME="migrate-oracle-to-postgre_default"
fi

echo "Using Docker network: $NETWORK_NAME"
echo ""

# Kiểm tra containers đang chạy
echo "1. Checking containers status..."
if ! docker ps | grep -q "oracle-db"; then
    echo "   ❌ ERROR: oracle-db container is not running!"
    echo "   Please run: docker-compose up -d"
    exit 1
fi

if ! docker ps | grep -q "postgres-db"; then
    echo "   ❌ ERROR: postgres-db container is not running!"
    echo "   Please run: docker-compose up -d"
    exit 1
fi

echo "   ✅ Containers are running"
echo ""

# Test Oracle connection
echo "2. Testing Oracle connection..."
ORACLE_TEST=$(docker run --rm --network "$NETWORK_NAME" \
    -e ORACLE_HOME=/usr/lib/oracle/19.26/client64 \
    -e LD_LIBRARY_PATH=/usr/lib/oracle/19.26/client64/lib \
    -e TNS_ADMIN=/config \
    -v "$(pwd)/ora2pg/config:/config:ro" \
    georgmoser/ora2pg:latest \
    bash -c "unset NLS_LANG; ora2pg -t SHOW_VERSION -c /config/ora2pg.conf" 2>&1)

if echo "$ORACLE_TEST" | grep -q "Oracle"; then
    echo "   ✅ Oracle connection: SUCCESS"
    echo "$ORACLE_TEST" | head -5
else
    echo "   ❌ Oracle connection: FAILED"
    echo "$ORACLE_TEST"
    exit 1
fi
echo ""

# Test PostgreSQL connection
echo "3. Testing PostgreSQL connection..."
PG_TEST=$(docker run --rm --network "$NETWORK_NAME" \
    -e ORACLE_HOME=/usr/lib/oracle/19.26/client64 \
    -e LD_LIBRARY_PATH=/usr/lib/oracle/19.26/client64/lib \
    -e TNS_ADMIN=/config \
    -v "$(pwd)/ora2pg/config:/config:ro" \
    georgmoser/ora2pg:latest \
    bash -c "unset NLS_LANG; ora2pg -t SHOW_VERSION -c /config/ora2pg.conf" 2>&1)

if echo "$PG_TEST" | grep -q "PostgreSQL\|Postgres"; then
    echo "   ✅ PostgreSQL connection: SUCCESS"
    echo "$PG_TEST" | head -5
else
    echo "   ❌ PostgreSQL connection: FAILED"
    echo "$PG_TEST"
    exit 1
fi
echo ""

# Test Oracle schema access
echo "4. Testing Oracle schema access..."
ORACLE_SCHEMA_TEST=$(docker run --rm --network "$NETWORK_NAME" \
    -e ORACLE_HOME=/usr/lib/oracle/19.26/client64 \
    -e LD_LIBRARY_PATH=/usr/lib/oracle/19.26/client64/lib \
    -e TNS_ADMIN=/config \
    -v "$(pwd)/ora2pg/config:/config:ro" \
    georgmoser/ora2pg:latest \
    bash -c "unset NLS_LANG; ora2pg -t SHOW_TABLE -c /config/ora2pg.conf" 2>&1 | head -20)

if echo "$ORACLE_SCHEMA_TEST" | grep -q "TABLE\|table"; then
    echo "   ✅ Oracle schema access: SUCCESS"
    echo "   Found tables:"
    echo "$ORACLE_SCHEMA_TEST" | grep -i "TABLE" | head -10
else
    echo "   ⚠️  Oracle schema access: Check if schema TRUYENNHIEM_NEW exists"
    echo "$ORACLE_SCHEMA_TEST" | head -10
fi
echo ""

# Test PostgreSQL schema access
echo "5. Testing PostgreSQL schema access..."
PG_SCHEMA_TEST=$(docker exec postgres-db psql -U postgres -d db_postgres -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'TRUYENNHIEM_NEW';" 2>&1)

if echo "$PG_SCHEMA_TEST" | grep -qE "[0-9]+"; then
    TABLE_COUNT=$(echo "$PG_SCHEMA_TEST" | grep -oE "[0-9]+" | head -1)
    echo "   ✅ PostgreSQL schema access: SUCCESS"
    echo "   Found $TABLE_COUNT tables in schema TRUYENNHIEM_NEW"
else
    echo "   ⚠️  PostgreSQL schema access: Check if schema TRUYENNHIEM_NEW exists"
    echo "$PG_SCHEMA_TEST"
fi
echo ""

echo "=========================================="
echo "Connection tests completed!"
echo "=========================================="
