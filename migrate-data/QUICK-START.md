# 🚀 Quick Start Guide - Migrate Data Oracle → PostgreSQL

Hướng dẫn nhanh để migrate data từ Oracle sang PostgreSQL bằng Ora2Pg.

## 📋 Prerequisites

- Docker và Docker Compose đã được cài đặt
- Oracle và PostgreSQL containers đang chạy
- Schema đã được migrate sang PostgreSQL (bằng SCT hoặc tool khác)

## ⚡ Các bước thực hiện

### 1. Kiểm tra containers đang chạy

```bash
docker-compose up -d
docker ps | grep -E "oracle-db|postgres-db"
```

### 2. Test kết nối

**Linux/Mac:**
```bash
cd migrate-data/scripts
chmod +x *.sh
./test-connections.sh
```

**Windows (PowerShell):**
```powershell
cd migrate-data\scripts
.\test-connections.ps1
```

### 3. Chạy migration

**Linux/Mac:**
```bash
./migrate-data.sh
```

**Windows (PowerShell):**
```powershell
.\migrate-data.ps1
```

### 4. Validate data

**Linux/Mac:**
```bash
./validate-data.sh
```

**Windows (PowerShell):**
```powershell
.\validate-data.ps1
```

## 📁 Cấu trúc thư mục

```
project-root/
├── migrate-data/
│   └── scripts/              # Chỉ chứa scripts
│       ├── test-connections.sh
│       ├── migrate-data.sh
│       ├── validate-data.sh
│       └── *.ps1             # PowerShell versions
├── ora2pg/
│   ├── config/
│   │   └── ora2pg.conf      # File cấu hình Ora2Pg
│   ├── output/               # Output files từ Ora2Pg
│   ├── logs/                 # Log files
│   └── backup/               # PostgreSQL backups
└── docker-compose.yaml
```

## 🔧 Cấu hình nhanh

File `ora2pg/config/ora2pg.conf` đã được cấu hình sẵn với:
- Oracle: `oracle-db:1521/XEPDB1`
- PostgreSQL: `postgres-db:5432/db_postgres`
- Schema: `TRUYENNHIEM_NEW`

Nếu cần thay đổi, chỉnh sửa file `ora2pg/config/ora2pg.conf`.

## ⚠️ Lưu ý quan trọng

1. **Backup trước khi migrate**: Script tự động backup PostgreSQL, nhưng nên backup thủ công nếu cần
2. **Schema phải tồn tại**: Đảm bảo schema `TRUYENNHIEM_NEW` và các tables đã được tạo trong PostgreSQL
3. **Kiểm tra logs**: Nếu có lỗi, kiểm tra files trong `logs/`
4. **Disable constraints**: Script tự động disable/enable triggers và foreign keys

## 🐛 Troubleshooting

### Lỗi kết nối Oracle

```bash
# Kiểm tra Oracle container
docker logs oracle-db

# Test kết nối thủ công
docker exec -it oracle-db sqlplus system/123456@XEPDB1
```

### Lỗi kết nối PostgreSQL

```bash
# Kiểm tra PostgreSQL container
docker logs postgres-db

# Test kết nối thủ công
docker exec -it postgres-db psql -U postgres -d db_postgres
```

### Data không khớp

1. Kiểm tra log files trong `logs/`
2. So sánh số lượng records từng table
3. Kiểm tra encoding (phải là UTF-8)
4. Kiểm tra data types conversion

## 📚 Tài liệu tham khảo

Xem file `README.md` để biết chi tiết đầy đủ về:
- Cấu hình Ora2Pg
- Các options migration
- Best practices
- Xử lý vấn đề thường gặp

## 🆘 Hỗ trợ

Nếu gặp vấn đề:
1. Kiểm tra logs trong `migrate-data/logs/`
2. Kiểm tra container logs: `docker logs oracle-db`, `docker logs postgres-db`
3. Xem hướng dẫn chi tiết trong `README.md`
