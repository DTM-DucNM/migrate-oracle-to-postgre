# PowerShell script tự động migrate data từ Oracle sang PostgreSQL

$ErrorActionPreference = "Stop"

# Configuration
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# projectDir phải là parent của migrate-data, không phải migrate-data chính nó
$projectDir = Split-Path -Parent (Split-Path -Parent $scriptDir)
$configDir = Join-Path $projectDir "ora2pg\config"
$outputDir = Join-Path $projectDir "migrate-data\output"
$logsDir = Join-Path $projectDir "migrate-data\logs"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $logsDir "migration-$timestamp.log"

# Create directories if not exist
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

# Get network name
$networkName = (docker network ls | Select-String "migrate-oracle-to-postgre").ToString().Split()[0]
if (-not $networkName) {
    $networkName = "migrate-oracle-to-postgre_default"
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Oracle to PostgreSQL Data Migration" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:"
Write-Host "  Network: $networkName"
Write-Host "  Config: $configDir\ora2pg.conf"
Write-Host "  Output: $outputDir"
Write-Host "  Log: $logFile"
Write-Host ""

# Step 1: Check containers
Write-Host "[1/5] Checking containers..." -ForegroundColor Yellow
$oracleRunning = docker ps | Select-String "oracle-db"
$postgresRunning = docker ps | Select-String "postgres-db"

if (-not $oracleRunning) {
    Write-Host "ERROR: oracle-db container is not running!" -ForegroundColor Red
    exit 1
}
if (-not $postgresRunning) {
    Write-Host "ERROR: postgres-db container is not running!" -ForegroundColor Red
    exit 1
}
Write-Host "Containers are running" -ForegroundColor Green
Write-Host ""

# Step 2: Test connections
Write-Host "[2/5] Testing connections..." -ForegroundColor Yellow
& "$scriptDir\test-connections.ps1" | Tee-Object -FilePath $logFile -Append
if ($LASTEXITCODE -ne 0) {
    Write-Host "Connection test failed! Check log: $logFile" -ForegroundColor Red
    exit 1
}
Write-Host "Connections OK" -ForegroundColor Green
Write-Host ""

# Step 3: Disable triggers and foreign keys
Write-Host "[3/5] Disabling triggers and foreign keys in PostgreSQL..." -ForegroundColor Yellow
$disableSQL = @"
SET session_replication_role = 'replica';
DO `$`$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'TRUYENNHIEM_NEW') LOOP
        EXECUTE 'ALTER TABLE ' || quote_ident('TRUYENNHIEM_NEW') || '.' || quote_ident(r.tablename) || ' DISABLE TRIGGER ALL';
    END LOOP;
END `$`$;
"@

$disableSQL | docker exec -i postgres-db psql -U postgres -d db_postgres | Out-Null
Write-Host "Triggers and foreign keys disabled" -ForegroundColor Green
Write-Host ""

# Step 4: Export and import data
Write-Host "[4/5] Exporting data from Oracle and importing to PostgreSQL..." -ForegroundColor Yellow
Write-Host "This may take a while depending on data size..." -ForegroundColor Yellow
Write-Host ""

$exportLog = Join-Path $logsDir "export-$timestamp.log"
$importLog = Join-Path $logsDir "import-$timestamp.log"

# Run Ora2Pg migration
# Kiểm tra file config có tồn tại không
if (-not (Test-Path "$configDir\ora2pg.conf")) {
    Write-Host "ERROR: Config file not found at: $configDir\ora2pg.conf" -ForegroundColor Red
    Write-Host "Please check if ora2pg/config/ora2pg.conf exists" -ForegroundColor Yellow
    Write-Host "Project dir: $projectDir" -ForegroundColor Yellow
    Write-Host "Config dir: $configDir" -ForegroundColor Yellow
    exit 1
}

# Sử dụng đường dẫn tuyệt đối cho Windows
# Docker Desktop trên Windows tự động convert Windows path sang Linux path
$configPath = (Resolve-Path $configDir).Path
$outputPath = (Resolve-Path $outputDir).Path

Write-Host "Project dir: $projectDir" -ForegroundColor Gray
Write-Host "Config dir: $configDir" -ForegroundColor Gray
Write-Host "Config path (absolute): $configPath" -ForegroundColor Gray
Write-Host "Output path (absolute): $outputPath" -ForegroundColor Gray
Write-Host "Config file exists: $(Test-Path "$configDir\ora2pg.conf")" -ForegroundColor Gray
Write-Host ""

# Chạy Ora2Pg và capture output
Write-Host "Running Ora2Pg migration..." -ForegroundColor Cyan
# Set ORACLE_HOME và LD_LIBRARY_PATH, KHÔNG set NLS_LANG để tránh lỗi ORA-12705
# Mount logs volume để Ora2Pg có thể ghi log vào đó (nếu cần)
$logsPath = (Resolve-Path $logsDir).Path
$ora2pgOutput = docker run --rm --network $networkName `
    -e ORACLE_HOME=/usr/lib/oracle/19.26/client64 `
    -e LD_LIBRARY_PATH=/usr/lib/oracle/19.26/client64/lib `
    -e TNS_ADMIN=/config `
    -v "${configPath}:/config:ro" `
    -v "${outputPath}:/data" `
    -v "${logsPath}:/logs" `
    georgmoser/ora2pg:latest `
    bash -c "unset NLS_LANG; ora2pg -c /config/ora2pg.conf --debug" 2>&1

# Lưu output vào log file trên host (backup)
$ora2pgOutput | Out-File -FilePath $exportLog -Encoding UTF8

# Kiểm tra exit code
$exitCode = $LASTEXITCODE

# Hiển thị output và highlight errors
$hasError = $false
$ora2pgOutput | ForEach-Object {
    if ($_ -match "FATAL|ERROR|Aborting") {
        Write-Host $_ -ForegroundColor Red
        $hasError = $true
    } elseif ($_ -match "WARNING") {
        Write-Host $_ -ForegroundColor Yellow
    } else {
        Write-Host $_
    }
}

# Nếu có lỗi, hiển thị thêm thông tin
if ($hasError -or $exitCode -ne 0) {
    Write-Host ""
    Write-Host "Error detected! Check full log: $exportLog" -ForegroundColor Red
    Write-Host "Last 20 lines of log:" -ForegroundColor Yellow
    Get-Content $exportLog -Tail 20 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
}

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "Data export completed" -ForegroundColor Green
    
    # Import data files
    Write-Host "Importing data files to PostgreSQL..." -ForegroundColor Yellow
    
    $sqlFiles = Get-ChildItem -Path $outputDir -Filter "*.sql" -File | Sort-Object Name
    
    if ($sqlFiles.Count -eq 0) {
        Write-Host "No SQL files found in $outputDir" -ForegroundColor Yellow
        Write-Host "Check if Ora2Pg generated files in COPY format (.csv or .dat)" -ForegroundColor Yellow
    } else {
        $imported = 0
        $failed = 0
        
        foreach ($sqlFile in $sqlFiles) {
            Write-Host "  Importing $($sqlFile.Name)..." -ForegroundColor Yellow
            
            Get-Content $sqlFile.FullName | docker exec -i postgres-db psql -U postgres -d db_postgres -v ON_ERROR_STOP=1 2>&1 | Out-File -FilePath $importLog -Append
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    $($sqlFile.Name) imported" -ForegroundColor Green
                $imported++
            } else {
                Write-Host "    $($sqlFile.Name) failed" -ForegroundColor Red
                $failed++
            }
        }
        
        Write-Host ""
        Write-Host "Import summary:"
        Write-Host "  Imported: $imported files" -ForegroundColor Green
        if ($failed -gt 0) {
            Write-Host "  Failed: $failed files" -ForegroundColor Red
            Write-Host "  Check log: $importLog" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "Data export failed!" -ForegroundColor Red
    Write-Host "Check log: $exportLog" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# Step 5: Enable triggers and foreign keys
Write-Host "[5/5] Enabling triggers and foreign keys in PostgreSQL..." -ForegroundColor Yellow
$enableSQL = @"
SET session_replication_role = 'origin';
DO `$`$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'TRUYENNHIEM_NEW') LOOP
        EXECUTE 'ALTER TABLE ' || quote_ident('TRUYENNHIEM_NEW') || '.' || quote_ident(r.tablename) || ' ENABLE TRIGGER ALL';
    END LOOP;
END `$`$;
"@

$enableSQL | docker exec -i postgres-db psql -U postgres -d db_postgres | Out-Null
Write-Host "Triggers and foreign keys enabled" -ForegroundColor Green
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Migration completed!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Validate data: .\scripts\validate-data.ps1"
Write-Host "  2. Check logs: $logFile"
Write-Host "  3. Check export log: $exportLog"
Write-Host "  4. Check import log: $importLog"
Write-Host ""
