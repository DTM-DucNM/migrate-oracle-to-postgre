# Hướng Dẫn Migrate Data từ Oracle sang PostgreSQL bằng Ora2Pg

## 📋 Mục Lục

1. [Giới thiệu Ora2Pg](#1-giới-thiệu-ora2pg)
2. [Kiến trúc & Luồng Migration](#2-kiến-trúc--luồng-migration)
3. [Cài đặt Ora2Pg với Docker](#3-cài-đặt-ora2pg-với-docker)
4. [Cấu hình Ora2Pg](#4-cấu-hình-ora2pg)
5. [Migration DATA](#5-migration-data)
6. [Thực thi Migration](#6-thực-thi-migration)
7. [Kiểm tra & Validate](#7-kiểm-tra--validate)
8. [Xử lý Vấn đề Thường Gặp](#8-xử-lý-vấn-đề-thường-gặp)
9. [Best Practices](#9-best-practices)

---

## 1. Giới thiệu Ora2Pg

### Ora2Pg là gì?

**Ora2Pg** là một công cụ mã nguồn mở, miễn phí được viết bằng Perl, chuyên dụng để migrate database từ Oracle sang PostgreSQL. Tool này được phát triển bởi Gilles Darold và được cộng đồng sử dụng rộng rãi.

**Tính năng chính:**
- Export schema (tables, views, sequences, indexes, constraints, triggers, functions, procedures)
- Export data từ Oracle và import vào PostgreSQL
- Convert Oracle SQL syntax sang PostgreSQL
- Hỗ trợ nhiều loại migration: SCHEMA, TABLE, DATA, COPY, INSERT, etc.
- Tự động convert data types (NUMBER → NUMERIC, DATE → TIMESTAMP, etc.)
- Hỗ trợ parallel export/import để tăng tốc độ

### Vì sao Ora2Pg phù hợp cho việc migrate data Oracle → PostgreSQL?

1. **Chuyên biệt cho Oracle → PostgreSQL**: Tool được thiết kế đặc biệt cho migration này, hiểu rõ sự khác biệt giữa 2 hệ thống
2. **Tự động convert data types**: Xử lý tự động các chuyển đổi phức tạp như NUMBER, DATE, CLOB, BLOB
3. **Hỗ trợ data lớn**: Có thể xử lý hàng triệu records với batch processing
4. **Encoding support**: Xử lý tốt UTF-8 và các encoding khác
5. **Flexible configuration**: Cấu hình linh hoạt qua file config
6. **Docker support**: Có sẵn Docker image, dễ triển khai
7. **Active community**: Được maintain tích cực, có nhiều tài liệu

---

## 2. Kiến trúc & Luồng Migration

### Luồng Migration

```
┌─────────────┐         ┌──────────────┐         ┌──────────────┐
│  Oracle DB  │ ──────> │   Ora2Pg     │ ──────> │ PostgreSQL   │
│  (Source)   │  READ   │  (Tool)      │  WRITE  │  (Target)    │
└─────────────┘         └──────────────┘         └──────────────┘
     │                        │                        │
     │                        │                        │
  Data Export            Data Transform          Data Import
  (SELECT)               (Convert types)         (INSERT/COPY)
```

### Quy trình chi tiết:

1. **Kết nối Oracle**: Ora2Pg kết nối tới Oracle DB để đọc data
2. **Export Data**: Ora2Pg export data từ các bảng Oracle (có thể export ra SQL file hoặc COPY format)
3. **Transform Data**: 
   - Convert data types (NUMBER → NUMERIC, DATE → TIMESTAMP)
   - Handle encoding (UTF-8)
   - Convert NULL values
4. **Kết nối PostgreSQL**: Ora2Pg kết nối tới PostgreSQL DB
5. **Import Data**: Ora2Pg import data vào PostgreSQL (sử dụng COPY hoặc INSERT)

### Trong môi trường Docker:

```
docker network: default (hoặc custom network)
├── oracle-db (container)     :1521
├── postgres-db (container)    :5432
└── ora2pg (container)         : kết nối tới cả 2 DB
```

---

## 3. Cài đặt Ora2Pg với Docker

### 3.1. Thêm Ora2Pg service vào docker-compose.yaml

Thêm service `ora2pg` vào file `docker-compose.yaml`:

```yaml
services:
  # ... existing services ...
  
  ora2pg:
    image: georgmoser/ora2pg:latest
    container_name: ora2pg-migration
    volumes:
      - ./ora2pg/config:/config:ro
      - ./ora2pg/output:/data
    networks:
      - default
    depends_on:
      - oracle
      - postgres
    restart: "no"
```

**Giải thích:**
- `volumes`: 
  - `/config:ro`: Mount folder chứa file `ora2pg.conf` (read-only)
  - `/data`: Mount folder để lưu output files
- `networks`: Sử dụng cùng network với Oracle và PostgreSQL để có thể kết nối
- `depends_on`: Đảm bảo Oracle và PostgreSQL đã chạy trước khi chạy Ora2Pg

### 3.2. Tạo cấu trúc thư mục

```bash
mkdir -p migrate-data/scripts
mkdir -p ora2pg/config
mkdir -p ora2pg/output
mkdir -p ora2pg/logs
mkdir -p ora2pg/backup
```

### 3.3. Pull Docker image

```bash
docker pull georgmoser/ora2pg:latest
```

---

## 4. Cấu hình Ora2Pg

### 4.1. Thông tin kết nối từ docker-compose.yaml

Từ file `docker-compose.yaml`, ta có:

**Oracle:**
- Host: `oracle-db` (container name)
- Port: `1521`
- Service Name: `XEPDB1`
- User: `SYSTEM` (hoặc user khác)
- Password: `123456`
- Schema: `TRUYENNHIEM_NEW` (từ import script)

**PostgreSQL:**
- Host: `postgres-db` (container name)
- Port: `5432`
- Database: `db_postgres`
- User: `postgres`
- Password: `123456`
- Schema: `TRUYENNHIEM_NEW` (giả sử schema đã được tạo bằng SCT)

### 4.2. Tạo file ora2pg.conf

File cấu hình `ora2pg.conf` được đặt trong `ora2pg/config/ora2pg.conf`

**Lưu ý quan trọng:**
- Trong Docker, hostname là **container name**, không phải `localhost`
- Oracle DSN format: `dbi:Oracle:host=<host>;sid=<service_name>;port=<port>`
- PostgreSQL DSN format: `dbi:Pg:dbname=<dbname>;host=<host>;port=<port>`

Xem file `ora2pg.conf` mẫu đầy đủ trong phần tiếp theo.

---

## 5. Migration DATA

### 5.1. Cấu hình cho DATA migration

Trong file `ora2pg.conf`, các tham số quan trọng cho DATA migration:

```conf
# Loại migration: DATA (chỉ migrate data, không migrate schema)
TYPE DATA

# Schema Oracle cần migrate
SCHEMA TRUYENNHIEM_NEW

# Tables cần migrate (để trống = tất cả tables trong schema)
# TABLES table1,table2,table3

# Số records commit một lần (quan trọng cho performance)
COMMIT 10000

# Batch size cho COPY command (PostgreSQL)
COPY 10000

# Format export: COPY (nhanh nhất) hoặc INSERT
DATA_TYPE COPY
```

### 5.2. Giải thích các options quan trọng

| Option | Mô tả | Giá trị khuyến nghị |
|--------|-------|---------------------|
| `TYPE` | Loại migration | `DATA` (chỉ data) hoặc `COPY` (data + COPY format) |
| `SCHEMA` | Schema Oracle cần migrate | Tên schema của bạn |
| `TABLES` | Danh sách tables (cách nhau bằng dấu phẩy) | Để trống = tất cả tables |
| `COMMIT` | Số records commit một lần | `10000` (cân bằng giữa performance và memory) |
| `COPY` | Batch size cho COPY command | `10000` (nhanh hơn INSERT) |
| `DATA_TYPE` | Format export | `COPY` (nhanh nhất) hoặc `INSERT` |
| `FILE_PER_TABLE` | Tạo file riêng cho mỗi table | `1` (dễ debug và retry) |
| `TRUNCATE_TABLE` | Truncate table trước khi import | `1` (nếu muốn import lại) |
| `DISABLE_TRIGGERS` | Disable triggers khi import | `1` (tăng tốc độ import) |

### 5.3. Các options khác quan trọng

```conf
# Encoding
NLS_LANG UTF8

# Parallel export (nếu có nhiều tables)
JOBS 4

# Log level
LOG_ON_ERROR 1

# Output directory
OUTPUT_DIR /data

# Disable foreign key checks khi import
DISABLE_FK 1
```

---

## 6. Thực thi Migration

### 6.1. Chuẩn bị

**Bước 1: Đảm bảo containers đang chạy**

```bash
docker-compose up -d
```

**Bước 2: Kiểm tra containers**

```bash
docker ps | grep -E "oracle-db|postgres-db"
```

### 6.2. Test kết nối Oracle

```bash
# Test kết nối Oracle từ container ora2pg
docker run --rm --network migrate-oracle-to-postgre_default \
  georgmoser/ora2pg:latest \
  ora2pg -t SHOW_VERSION -c /config/ora2pg.conf
```

Hoặc sử dụng script `test-connections.sh` (xem phần scripts).

### 6.3. Test kết nối PostgreSQL

```bash
# Test kết nối PostgreSQL
docker run --rm --network migrate-oracle-to-postgre_default \
  -v ./ora2pg/config:/config:ro \
  georgmoser/ora2pg:latest \
  ora2pg -t SHOW_VERSION -c /config/ora2pg.conf
```

### 6.4. Export Data từ Oracle

**Lệnh cơ bản:**

```bash
docker run --rm --network migrate-oracle-to-postgre_default \
  -v ./ora2pg/config:/config:ro \
  -v ./ora2pg/output:/data \
  georgmoser/ora2pg:latest \
  ora2pg -c /config/ora2pg.conf
```

**Lệnh với options:**

```bash
docker run --rm --network migrate-oracle-to-postgre_default \
  -v ./ora2pg/config:/config:ro \
  -v ./ora2pg/output:/data \
  georgmoser/ora2pg:latest \
  ora2pg -c /config/ora2pg.conf \
    --type COPY \
    --schema TRUYENNHIEM_NEW \
    --jobs 4 \
    --debug
```

### 6.5. Import Data vào PostgreSQL

Sau khi export, Ora2Pg sẽ tạo các file SQL. Import vào PostgreSQL:

```bash
# Import từ file SQL
docker exec -i postgres-db psql -U postgres -d db_postgres < ora2pg/output/data.sql

# Hoặc import từng file (nếu FILE_PER_TABLE=1)
for file in ora2pg/output/*.sql; do
  echo "Importing $file..."
  docker exec -i postgres-db psql -U postgres -d db_postgres < "$file"
done
```

**Lưu ý:** Nếu sử dụng `DATA_TYPE COPY`, Ora2Pg sẽ tạo file COPY format, cần import bằng `psql \copy` command.

### 6.6. Sử dụng Script tự động

Xem các script trong folder `migrate-data/scripts/`:
- `test-connections.sh`: Test kết nối Oracle và PostgreSQL
- `migrate-data.sh`: Script tự động migrate data
- `validate-data.sh`: Script validate data sau migration

---

## 7. Kiểm tra & Validate

### 7.1. So sánh số lượng records

**Oracle:**

```sql
-- Kết nối Oracle
docker exec -it oracle-db sqlplus system/123456@XEPDB1

-- Đếm records trong schema
SELECT 
    table_name,
    num_rows
FROM all_tables 
WHERE owner = 'TRUYENNHIEM_NEW'
ORDER BY table_name;
```

**PostgreSQL:**

```sql
-- Kết nối PostgreSQL
docker exec -it postgres-db psql -U postgres -d db_postgres

-- Đếm records trong schema
SELECT 
    schemaname,
    tablename,
    n_live_tup as row_count
FROM pg_stat_user_tables
WHERE schemaname = 'TRUYENNHIEM_NEW'
ORDER BY tablename;
```

### 7.2. SQL kiểm tra data

**So sánh số lượng records từng table:**

```sql
-- PostgreSQL
SELECT 
    'SELECT COUNT(*) FROM ' || schemaname || '.' || tablename || ';' as count_query
FROM pg_tables
WHERE schemaname = 'TRUYENNHIEM_NEW';
```

**Kiểm tra data sample:**

```sql
-- So sánh sample data
-- Oracle
SELECT * FROM TRUYENNHIEM_NEW.table_name WHERE ROWNUM <= 10;

-- PostgreSQL
SELECT * FROM TRUYENNHIEM_NEW.table_name LIMIT 10;
```

### 7.3. Phát hiện lỗi data

**Các cách phát hiện lỗi:**

1. **So sánh COUNT:**
   ```sql
   -- Tạo script so sánh COUNT giữa Oracle và PostgreSQL
   ```

2. **Kiểm tra NULL values:**
   ```sql
   SELECT column_name, COUNT(*) 
   FROM table_name 
   WHERE column_name IS NULL
   GROUP BY column_name;
   ```

3. **Kiểm tra data types:**
   ```sql
   -- PostgreSQL
   SELECT column_name, data_type 
   FROM information_schema.columns 
   WHERE table_schema = 'TRUYENNHIEM_NEW';
   ```

4. **Kiểm tra constraints:**
   ```sql
   -- Kiểm tra foreign key violations
   SELECT * FROM table_name 
   WHERE foreign_key_column NOT IN (SELECT id FROM referenced_table);
   ```

---

## 8. Xử lý Vấn đề Thường Gặp

### 8.1. Encoding (UTF-8)

**Vấn đề:** Ký tự đặc biệt, tiếng Việt bị lỗi encoding.

**Giải pháp:**

```conf
# Trong ora2pg.conf
NLS_LANG UTF8
PG_DSN dbi:Pg:dbname=db_postgres;host=postgres-db;port=5432;client_encoding=UTF8
```

**Kiểm tra encoding:**

```sql
-- PostgreSQL
SHOW client_encoding;
-- Phải là UTF8
```

### 8.2. DATE / TIMESTAMP

**Vấn đề:** Oracle DATE vs PostgreSQL TIMESTAMP.

**Giải pháp:**

Ora2Pg tự động convert:
- Oracle `DATE` → PostgreSQL `TIMESTAMP`
- Oracle `TIMESTAMP` → PostgreSQL `TIMESTAMP`

**Nếu có vấn đề timezone:**

```conf
# Trong ora2pg.conf
PG_DSN dbi:Pg:dbname=db_postgres;host=postgres-db;port=5432;timezone=UTC
```

### 8.3. NUMBER → NUMERIC

**Vấn đề:** Oracle NUMBER có thể có precision/scale khác nhau.

**Giải pháp:**

Ora2Pg tự động convert:
- `NUMBER` → `NUMERIC`
- `NUMBER(p,s)` → `NUMERIC(p,s)`

**Kiểm tra:**

```sql
-- Oracle
SELECT column_name, data_type, data_precision, data_scale
FROM all_tab_columns
WHERE owner = 'TRUYENNHIEM_NEW';

-- PostgreSQL
SELECT column_name, data_type, numeric_precision, numeric_scale
FROM information_schema.columns
WHERE table_schema = 'TRUYENNHIEM_NEW';
```

### 8.4. Constraint / Foreign Key / Trigger

**Vấn đề:** Foreign key constraint khiến import bị lỗi.

**Giải pháp:**

```conf
# Disable foreign keys khi import
DISABLE_FK 1

# Disable triggers khi import
DISABLE_TRIGGERS 1
```

**Sau khi import xong, enable lại:**

```sql
-- PostgreSQL: Enable foreign keys
ALTER TABLE table_name ENABLE TRIGGER ALL;

-- Hoặc enable từng constraint
ALTER TABLE table_name ENABLE CONSTRAINT constraint_name;
```

### 8.5. Performance khi migrate data lớn

**Vấn đề:** Migrate data lớn (hàng triệu records) chậm.

**Giải pháp:**

1. **Tăng COMMIT và COPY size:**
   ```conf
   COMMIT 50000
   COPY 50000
   ```

2. **Sử dụng parallel jobs:**
   ```conf
   JOBS 4
   ```

3. **Disable indexes tạm thời:**
   ```sql
   -- Trước khi import
   ALTER TABLE table_name DISABLE TRIGGER ALL;
   
   -- Sau khi import
   REINDEX TABLE table_name;
   ALTER TABLE table_name ENABLE TRIGGER ALL;
   ```

4. **Migrate theo batch (từng table):**
   ```conf
   TABLES table1
   # Import table1
   TABLES table2
   # Import table2
   ```

5. **Sử dụng COPY thay vì INSERT:**
   ```conf
   DATA_TYPE COPY
   ```

---

## 9. Best Practices

### 9.1. Backup trước khi migrate

**PostgreSQL backup:**

```bash
# Backup schema
docker exec postgres-db pg_dump -U postgres -d db_postgres \
  --schema=TRUYENNHIEM_NEW \
  --schema-only \
  > backup-schema-$(date +%Y%m%d).sql

# Backup data (nếu đã có data)
docker exec postgres-db pg_dump -U postgres -d db_postgres \
  --schema=TRUYENNHIEM_NEW \
  --data-only \
  > backup-data-$(date +%Y%m%d).sql
```

### 9.2. Disable constraint & trigger khi import

**Trước khi import:**

```sql
-- PostgreSQL
-- Disable all triggers trong schema
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'TRUYENNHIEM_NEW') LOOP
        EXECUTE 'ALTER TABLE ' || quote_ident(r.tablename) || ' DISABLE TRIGGER ALL';
    END LOOP;
END $$;

-- Hoặc disable foreign keys
SET session_replication_role = 'replica';
```

**Sau khi import:**

```sql
-- Enable lại triggers
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'TRUYENNHIEM_NEW') LOOP
        EXECUTE 'ALTER TABLE ' || quote_ident(r.tablename) || ' ENABLE TRIGGER ALL';
    END LOOP;
END $$;

-- Enable foreign keys
SET session_replication_role = 'origin';
```

### 9.3. Migrate theo batch

**Chiến lược:**

1. **Migrate tables không có foreign key trước:**
   ```conf
   TABLES table_without_fk1,table_without_fk2
   ```

2. **Migrate tables có foreign key sau:**
   ```conf
   TABLES table_with_fk1,table_with_fk2
   ```

3. **Migrate theo thứ tự dependency:**
   - Parent tables trước
   - Child tables sau

### 9.4. Log & Rollback Strategy

**Log migration:**

```bash
# Chạy với log file
docker run --rm --network migrate-oracle-to-postgre_default \
  -v ./ora2pg/config:/config:ro \
  -v ./ora2pg/output:/data \
  -v ./ora2pg/logs:/logs \
  georgmoser/ora2pg:latest \
  ora2pg -c /config/ora2pg.conf 2>&1 | tee /logs/migration-$(date +%Y%m%d-%H%M%S).log
```

**Rollback strategy:**

1. **Backup trước khi migrate** (đã nói ở trên)
2. **Sử dụng transaction:**
   ```sql
   BEGIN;
   -- Import data
   -- Nếu có lỗi:
   ROLLBACK;
   -- Nếu thành công:
   COMMIT;
   ```
3. **Import từng table:**
   - Dễ rollback từng table
   - Dễ debug

### 9.5. Checklist Migration

- [ ] Backup PostgreSQL database
- [ ] Test kết nối Oracle
- [ ] Test kết nối PostgreSQL
- [ ] Disable triggers và foreign keys
- [ ] Export data từ Oracle
- [ ] Validate exported data (số lượng records)
- [ ] Import data vào PostgreSQL
- [ ] Validate imported data
- [ ] So sánh số lượng records
- [ ] Enable lại triggers và foreign keys
- [ ] Test application với data mới

---

## 📝 Tài liệu tham khảo

- [Ora2Pg Official Documentation](https://ora2pg.darold.net/documentation.html)
- [Docker Image: georgmoser/ora2pg](https://hub.docker.com/r/georgmoser/ora2pg)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

---

## 🆘 Hỗ trợ

Nếu gặp vấn đề, kiểm tra:
1. Log files trong `ora2pg/logs/`
2. Ora2Pg output trong `ora2pg/output/`
3. Container logs: `docker logs ora2pg-migration`
4. Database logs: `docker logs oracle-db` và `docker logs postgres-db`
