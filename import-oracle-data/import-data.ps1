<# 
 Script PowerShell để import dữ liệu vào Oracle database (chạy trong Docker)

 Các bước thực hiện:
 1. Kiểm tra container oracle-db có đang chạy
 2. Chờ database sẵn sàng
 3. Chạy script setup-oracle.sql (tạo user, directory, grant quyền,...)
 4. Chạy impdp để import 4 file dump
#>

Write-Host "Start import data from data folder to Oracle database (Windows/PowerShell)..." -ForegroundColor Cyan

# 1. Kiểm tra container có đang chạy không
$oracleRunning = docker ps --format "{{.Names}}" | Where-Object { $_ -eq "oracle-db" }

if (-not $oracleRunning) {
    Write-Host "Error: Container oracle-db is not running!" -ForegroundColor Red
    Write-Host "Please run: docker-compose up -d oracle"
    exit 1
}

# 2. Chờ database sẵn sàng
Write-Host "Waiting for database to be ready (10 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# 3. Chạy setup script
if (-not (Test-Path -Path ".\setup-oracle.sql")) {
    Write-Host "Error: Cannot find setup-oracle.sql file in the current directory!" -ForegroundColor Red
    exit 1
}

Write-Host "Setting up Oracle database..." -ForegroundColor Cyan

try {
    Get-Content .\setup-oracle.sql | docker exec -i oracle-db sqlplus sys/123456@XEPDB1 as sysdba
}
catch {
    Write-Host "Error when running setup-oracle.sql: $_" -ForegroundColor Red
    exit 1
}

# 4. Import dữ liệu bằng impdp
Write-Host "Importing data (impdp)..." -ForegroundColor Cyan

# Kiểm tra file dump có tồn tại không
Write-Host "Checking dump files..." -ForegroundColor Yellow
$dumpFiles = @("truyennhiem_clean09122025_01.dmp", "truyennhiem_clean09122025_02.dmp", "truyennhiem_clean09122025_03.dmp", "truyennhiem_clean09122025_04.dmp")
foreach ($file in $dumpFiles) {
    $exists = docker exec oracle-db test -f "/opt/oracle/dump/$file"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Found: $file" -ForegroundColor Green
    } else {
        Write-Host "  Missing: $file" -ForegroundColor Red
    }
}

# Chạy impdp với đầy đủ tham số
Write-Host "Running impdp..." -ForegroundColor Yellow
$impdpResult = docker exec oracle-db bash -c "impdp system/123456@XEPDB1 DIRECTORY=DUMP_DIR DUMPFILE=truyennhiem_clean09122025_01.dmp,truyennhiem_clean09122025_02.dmp,truyennhiem_clean09122025_03.dmp,truyennhiem_clean09122025_04.dmp LOGFILE=truyennhiem_clean09122025_import.log SCHEMAS=TRUYENNHIEM_NEW REMAP_SCHEMA=TRUYENNHIEM_NEW:TRUYENNHIEM_NEW REMAP_TABLESPACE=TRUYENNHIEM_NEW:USERS TABLE_EXISTS_ACTION=REPLACE" 2>&1

$impdpResult | ForEach-Object { Write-Host $_ }

if ($LASTEXITCODE -eq 0) {
    Write-Host "Import completed successfully!" -ForegroundColor Green
} else {
    Write-Host "Import failed with exit code: $LASTEXITCODE" -ForegroundColor Red
}

Write-Host ""
Write-Host "Import completed! Check log file to see the result." -ForegroundColor Green
Write-Host "To see log, run the command:" -ForegroundColor Green
Write-Host "docker exec oracle-db cat /opt/oracle/dump/truyennhiem_clean09122025_import.log" -ForegroundColor Yellow

