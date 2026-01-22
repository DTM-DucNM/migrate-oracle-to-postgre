# 📝 Danh Sách Commands - Migrate Data Oracle → PostgreSQL

File này chứa các commands có thể copy & paste để chạy migration.

## 🔍 1. Test Kết Nối

### Linux/Mac (Bash)

```bash
cd migrate-data/scripts
chmod +x *.sh
./test-connections.sh
```

### Windows (PowerShell)

```powershell
cd migrate-data\scripts
.\test-connections.ps1
```

### Manual Test Oracle

```bash
# Test Oracle connection
docker exec -it oracle-db sqlplus system/123456@XEPDB1

# Kiểm tra tables trong schema
SELECT table_name FROM all_tables WHERE owner = 'TRUYENNHIEM_NEW';
```

### Manual Test PostgreSQL

```bash
# Test PostgreSQL connection
docker exec -it postgres-db psql -U postgres -d db_postgres

# Kiểm tra tables trong schema
SELECT tablename FROM pg_tables WHERE schemaname = 'TRUYENNHIEM_NEW';
```

---

## 🚀 2. Chạy Migration

### Sử dụng Script (Khuyến nghị)

**Linux/Mac:**
```bash
cd migrate-data/scripts
./migrate-data.sh
```

**Windows:**
```powershell
cd migrate-data\scripts
.\migrate-data.ps1
```

### Manual Migration với Docker Run

```bash
# Lấy network name
NETWORK_NAME=$(docker network ls | grep migrate-oracle-to-postgre | awk '{print $1}')

# Export data từ Oracle
docker run --rm --network $NETWORK_NAME \
  -v ./ora2pg/config:/config:ro \
  -v ./ora2pg/output:/data \
  georgmoser/ora2pg:latest \
  ora2pg -c /config/ora2pg.conf --debug
```

**Windows PowerShell:**
```powershell
$networkName = (docker network ls | Select-String "migrate-oracle-to-postgre").ToString().Split()[0]

docker run --rm --network $networkName `
  -v "${PWD}\migrate-data\config:/config:ro" `
  -v "${PWD}\migrate-data\output:/data" `
  georgmoser/ora2pg:latest `
  ora2pg -c /config/ora2pg.conf --debug
```

### Import Data vào PostgreSQL

**Sau khi export, import các file SQL:**

```bash
# Import tất cả file SQL
for file in ora2pg/output/*.sql; do
  echo "Importing $file..."
  docker exec -i postgres-db psql -U postgres -d db_postgres < "$file"
done
```

**Windows PowerShell:**
```powershell
Get-ChildItem -Path migrate-data\output\*.sql | ForEach-Object {
    Write-Host "Importing $($_.Name)..."
    Get-Content $_.FullName | docker exec -i postgres-db psql -U postgres -d db_postgres
}
```

---

## ✅ 3. Validate Data

### Sử dụng Script

**Linux/Mac:**
```bash
cd migrate-data/scripts
./validate-data.sh
```

**Windows:**
```powershell
cd migrate-data\scripts
.\validate-data.ps1
```

### Manual Validation

**So sánh số lượng records từng table:**

```sql
-- Oracle
SELECT 
    table_name,
    num_rows
FROM all_tables 
WHERE owner = 'TRUYENNHIEM_NEW'
ORDER BY table_name;

-- PostgreSQL
SELECT 
    tablename,
    n_live_tup as row_count
FROM pg_stat_user_tables
WHERE schemaname = 'TRUYENNHIEM_NEW'
ORDER BY tablename;
```

**So sánh COUNT từng table:**

```sql
-- Oracle
SELECT COUNT(*) FROM TRUYENNHIEM_NEW.table_name;

-- PostgreSQL
SELECT COUNT(*) FROM TRUYENNHIEM_NEW.table_name;
```

---

## 🔧 4. Các Commands Hữu Ích Khác

### Backup PostgreSQL

```bash
# Backup schema + data
docker exec postgres-db pg_dump -U postgres -d db_postgres \
  --schema=TRUYENNHIEM_NEW \
  > backup-$(date +%Y%m%d).sql

# Backup chỉ data
docker exec postgres-db pg_dump -U postgres -d db_postgres \
  --schema=TRUYENNHIEM_NEW \
  --data-only \
  > backup-data-$(date +%Y%m%d).sql
```

### Disable/Enable Triggers và Foreign Keys

```sql
-- Disable (trước khi import)
SET session_replication_role = 'replica';
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'TRUYENNHIEM_NEW') LOOP
        EXECUTE 'ALTER TABLE TRUYENNHIEM_NEW.' || quote_ident(r.tablename) || ' DISABLE TRIGGER ALL';
    END LOOP;
END $$;

-- Enable (sau khi import)
SET session_replication_role = 'origin';
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'TRUYENNHIEM_NEW') LOOP
        EXECUTE 'ALTER TABLE TRUYENNHIEM_NEW.' || quote_ident(r.tablename) || ' ENABLE TRIGGER ALL';
    END LOOP;
END $$;
```

### Kiểm tra Logs

```bash
# Ora2Pg logs
cat migrate-data/logs/migration-*.log

# Container logs
docker logs oracle-db
docker logs postgres-db
```

### Xem Output Files

```bash
# List các file đã export
ls -lh ora2pg/output/

# Xem nội dung một file SQL (first 50 lines)
head -50 ora2pg/output/table_name.sql
```

---

## 🐛 5. Troubleshooting Commands

### Test Ora2Pg Connection

```bash
# Test Oracle connection từ Ora2Pg
docker run --rm --network migrate-oracle-to-postgre_default \
  -v ./ora2pg/config:/config:ro \
  georgmoser/ora2pg:latest \
  ora2pg -t SHOW_VERSION -c /config/ora2pg.conf

# Test PostgreSQL connection từ Ora2Pg
docker run --rm --network migrate-oracle-to-postgre_default \
  -v ./ora2pg/config:/config:ro \
  georgmoser/ora2pg:latest \
  ora2pg -t SHOW_VERSION -c /config/ora2pg.conf
```

### Kiểm tra Network

```bash
# List networks
docker network ls

# Inspect network
docker network inspect migrate-oracle-to-postgre_default

# Kiểm tra containers trong network
docker network inspect migrate-oracle-to-postgre_default | grep -A 5 "Containers"
```

### Kiểm tra Containers

```bash
# List running containers
docker ps

# Check container status
docker ps | grep -E "oracle-db|postgres-db"

# View container logs
docker logs oracle-db --tail 50
docker logs postgres-db --tail 50
```

### Kiểm tra Data Types

```sql
-- Oracle: Xem data types
SELECT 
    column_name,
    data_type,
    data_length,
    data_precision,
    data_scale
FROM all_tab_columns
WHERE owner = 'TRUYENNHIEM_NEW'
ORDER BY table_name, column_id;

-- PostgreSQL: Xem data types
SELECT 
    table_name,
    column_name,
    data_type,
    character_maximum_length,
    numeric_precision,
    numeric_scale
FROM information_schema.columns
WHERE table_schema = 'TRUYENNHIEM_NEW'
ORDER BY table_name, ordinal_position;
```

---

## 📊 6. Performance Monitoring

### Kiểm tra số lượng records lớn

```sql
-- Oracle: Tables có nhiều records nhất
SELECT 
    table_name,
    num_rows
FROM all_tables 
WHERE owner = 'TRUYENNHIEM_NEW'
ORDER BY num_rows DESC NULLS LAST;

-- PostgreSQL: Tables có nhiều records nhất
SELECT 
    schemaname,
    tablename,
    n_live_tup,
    n_dead_tup,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname = 'TRUYENNHIEM_NEW'
ORDER BY n_live_tup DESC;
```

### Kiểm tra Index

```sql
-- PostgreSQL: List indexes
SELECT 
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'TRUYENNHIEM_NEW'
ORDER BY tablename, indexname;
```

---

## 💡 Tips

1. **Luôn test connection trước khi migrate**
2. **Backup PostgreSQL trước khi import**
3. **Disable triggers và foreign keys khi import để tăng tốc độ**
4. **Sử dụng COPY format thay vì INSERT (nhanh hơn nhiều)**
5. **Kiểm tra logs sau mỗi bước**
6. **Validate data sau khi migration hoàn tất**
