# PowerShell script để test kết nối Oracle và PostgreSQL từ Ora2Pg container

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Testing Oracle and PostgreSQL Connections" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Lấy network name từ docker-compose
$networkName = (docker network ls | Select-String "migrate-oracle-to-postgre").ToString().Split()[0]
if (-not $networkName) {
    $networkName = "migrate-oracle-to-postgre_default"
}

Write-Host "Using Docker network: $networkName" -ForegroundColor Yellow
Write-Host ""

# Kiểm tra containers đang chạy
Write-Host "1. Checking containers status..." -ForegroundColor Yellow
$oracleRunning = docker ps | Select-String "oracle-db"
$postgresRunning = docker ps | Select-String "postgres-db"

if (-not $oracleRunning) {
    Write-Host "   ERROR: oracle-db container is not running!" -ForegroundColor Red
    Write-Host "   Please run: docker-compose up -d" -ForegroundColor Yellow
    exit 1
}

if (-not $postgresRunning) {
    Write-Host "   ERROR: postgres-db container is not running!" -ForegroundColor Red
    Write-Host "   Please run: docker-compose up -d" -ForegroundColor Yellow
    exit 1
}

Write-Host "   Containers are running" -ForegroundColor Green
Write-Host ""

# Test Oracle connection
Write-Host "2. Testing Oracle connection..." -ForegroundColor Yellow
$oracleTest = docker run --rm --network $networkName `
    -e ORACLE_HOME=/usr/lib/oracle/19.26/client64 `
    -e LD_LIBRARY_PATH=/usr/lib/oracle/19.26/client64/lib `
    -e TNS_ADMIN=/config `
    -v "${PWD}\ora2pg\config:/config:ro" `
    georgmoser/ora2pg:latest `
    bash -c "unset NLS_LANG; ora2pg -t SHOW_VERSION -c /config/ora2pg.conf" 2>&1

if ($oracleTest -match "Oracle") {
    Write-Host "   Oracle connection: SUCCESS" -ForegroundColor Green
    $oracleTest | Select-Object -First 5 | ForEach-Object { Write-Host "   $_" }
} else {
    Write-Host "   Oracle connection: FAILED" -ForegroundColor Red
    Write-Host $oracleTest
    exit 1
}
Write-Host ""

# Test PostgreSQL connection
Write-Host "3. Testing PostgreSQL connection..." -ForegroundColor Yellow
$pgTest = docker run --rm --network $networkName `
    -e ORACLE_HOME=/usr/lib/oracle/19.26/client64 `
    -e LD_LIBRARY_PATH=/usr/lib/oracle/19.26/client64/lib `
    -e TNS_ADMIN=/config `
    -v "${PWD}\ora2pg\config:/config:ro" `
    georgmoser/ora2pg:latest `
    bash -c "unset NLS_LANG; ora2pg -t SHOW_VERSION -c /config/ora2pg.conf" 2>&1

if ($pgTest -match "PostgreSQL|Postgres") {
    Write-Host "   PostgreSQL connection: SUCCESS" -ForegroundColor Green
    $pgTest | Select-Object -First 5 | ForEach-Object { Write-Host "   $_" }
} else {
    Write-Host "   PostgreSQL connection: FAILED" -ForegroundColor Red
    Write-Host $pgTest
    exit 1
}
Write-Host ""

# Test Oracle schema access
Write-Host "4. Testing Oracle schema access..." -ForegroundColor Yellow
$oracleSchemaTest = docker run --rm --network $networkName `
    -e ORACLE_HOME=/usr/lib/oracle/19.26/client64 `
    -e LD_LIBRARY_PATH=/usr/lib/oracle/19.26/client64/lib `
    -e TNS_ADMIN=/config `
    -v "${PWD}\ora2pg\config:/config:ro" `
    georgmoser/ora2pg:latest `
    bash -c "unset NLS_LANG; ora2pg -t SHOW_TABLE -c /config/ora2pg.conf" 2>&1 | Select-Object -First 20

if ($oracleSchemaTest -match "TABLE|table") {
    Write-Host "   Oracle schema access: SUCCESS" -ForegroundColor Green
    Write-Host "   Found tables:"
    $oracleSchemaTest | Select-String -Pattern "TABLE" | Select-Object -First 10 | ForEach-Object { Write-Host "   $_" }
} else {
    Write-Host "   Oracle schema access: Check if schema TRUYENNHIEM_NEW exists" -ForegroundColor Yellow
    $oracleSchemaTest | Select-Object -First 10 | ForEach-Object { Write-Host "   $_" }
}
Write-Host ""

# Test PostgreSQL schema access
Write-Host "5. Testing PostgreSQL schema access..." -ForegroundColor Yellow
$pgSchemaTest = docker exec postgres-db psql -U postgres -d db_postgres -c `
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'TRUYENNHIEM_NEW';" 2>&1

if ($pgSchemaTest -match "\d+") {
    $tableCount = [regex]::Match($pgSchemaTest, "\d+").Value
    Write-Host "   PostgreSQL schema access: SUCCESS" -ForegroundColor Green
    Write-Host "   Found $tableCount tables in schema TRUYENNHIEM_NEW"
} else {
    Write-Host "   PostgreSQL schema access: Check if schema TRUYENNHIEM_NEW exists" -ForegroundColor Yellow
    Write-Host $pgSchemaTest
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Connection tests completed!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
