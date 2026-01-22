#!/bin/bash
# Script để import dữ liệu vào Oracle database

echo "Start import data from data folder to Oracle database..."

# Kiểm tra container có đang chạy không
if ! docker ps | grep -q oracle-db; then
    echo "Error: Container oracle-db is not running!"
    echo "Please run: docker-compose up -d"
    exit 1
fi

# Chờ database sẵn sàng
echo "Waiting for database to be ready..."
sleep 10

# Chạy setup script
echo "Setting up Oracle database..."
docker exec -i oracle-db sqlplus sys/123456@XEPDB1 as sysdba < setup-oracle.sql

# Import dữ liệu
echo "Importing data..."

# Kiểm tra file dump có tồn tại không
echo "Checking dump files..."
for file in truyennhiem_clean09122025_01.dmp truyennhiem_clean09122025_02.dmp truyennhiem_clean09122025_03.dmp truyennhiem_clean09122025_04.dmp; do
    if docker exec oracle-db test -f "/opt/oracle/dump/$file"; then
        echo "  Found: $file"
    else
        echo "  Missing: $file"
    fi
done

# Chạy impdp với đầy đủ tham số
echo "Running impdp..."
docker exec oracle-db bash -c "impdp system/123456@XEPDB1 DIRECTORY=DUMP_DIR DUMPFILE=truyennhiem_clean09122025_01.dmp,truyennhiem_clean09122025_02.dmp,truyennhiem_clean09122025_03.dmp,truyennhiem_clean09122025_04.dmp LOGFILE=truyennhiem_clean09122025_import.log SCHEMAS=TRUYENNHIEM_NEW REMAP_SCHEMA=TRUYENNHIEM_NEW:TRUYENNHIEM_NEW REMAP_TABLESPACE=TRUYENNHIEM_NEW:USERS TABLE_EXISTS_ACTION=REPLACE"

echo ""
echo "Import completed! Check log file to see the result."
echo "To see log: docker exec oracle-db cat /opt/oracle/dump/truyennhiem_clean09122025_import.log"
