# PowerShell script để validate data sau khi migration

$ErrorActionPreference = "Stop"

$schemaName = "TRUYENNHIEM_NEW"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Data Validation: Oracle vs PostgreSQL" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Function to get table count from Oracle
function Get-OracleCount {
    param($tableName)
    $query = "SELECT COUNT(*) FROM $schemaName.$tableName;"
    $result = docker exec oracle-db sqlplus -s system/123456@XEPDB1 @"
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
$query
EXIT
"@
    $result | Where-Object { $_ -match "^\d+$" } | Select-Object -First 1
}

# Function to get table count from PostgreSQL
function Get-PostgresCount {
    param($tableName)
    $query = "SELECT COUNT(*) FROM $schemaName.$tableName;"
    $result = docker exec postgres-db psql -U postgres -d db_postgres -t -c $query 2>$null
    ($result -replace '\s', '')
}

# Get list of tables from Oracle
Write-Host "[1/3] Getting list of tables from Oracle..." -ForegroundColor Blue
$oracleTablesQuery = @"
SET PAGESIZE 0
SET FEEDBACK OFF
SELECT table_name FROM all_tables WHERE owner = '$schemaName' ORDER BY table_name;
EXIT
"@

$oracleTablesOutput = docker exec oracle-db sqlplus -s system/123456@XEPDB1 $oracleTablesQuery
$oracleTables = $oracleTablesOutput | Where-Object { $_ -and $_ -notmatch "^-" -and $_ -notmatch "rows selected" -and $_ -notmatch "TABLE_NAME" } | ForEach-Object { $_.Trim() } | Where-Object { $_ }

if (-not $oracleTables) {
    Write-Host "No tables found in Oracle schema: $schemaName" -ForegroundColor Red
    exit 1
}

$tableCount = ($oracleTables | Measure-Object).Count
Write-Host "Found $tableCount tables in Oracle" -ForegroundColor Green
Write-Host ""

# Get list of tables from PostgreSQL
Write-Host "[2/3] Getting list of tables from PostgreSQL..." -ForegroundColor Blue
$postgresTablesQuery = "SELECT tablename FROM pg_tables WHERE schemaname = '$schemaName' ORDER BY tablename;"
$postgresTablesOutput = docker exec postgres-db psql -U postgres -d db_postgres -t -c $postgresTablesQuery
$postgresTables = $postgresTablesOutput | ForEach-Object { $_.Trim() } | Where-Object { $_ }

if (-not $postgresTables) {
    Write-Host "No tables found in PostgreSQL schema: $schemaName" -ForegroundColor Red
    exit 1
}

$pgTableCount = ($postgresTables | Measure-Object).Count
Write-Host "Found $pgTableCount tables in PostgreSQL" -ForegroundColor Green
Write-Host ""

# Compare table counts
Write-Host "[3/3] Comparing row counts..." -ForegroundColor Blue
Write-Host ""
Write-Host ("{0,-40} {1,15} {2,15} {3,10}" -f "TABLE_NAME", "ORACLE", "POSTGRES", "STATUS")
Write-Host ("{0,-40} {1,15} {2,15} {3,10}" -f ("=" * 40), ("=" * 15), ("=" * 15), ("=" * 10))

$matched = 0
$mismatched = 0
$missing = 0
$errors = 0

foreach ($table in $oracleTables) {
    # Check if table exists in PostgreSQL
    if ($postgresTables -contains $table) {
        # Get counts
        try {
            $oracleCount = Get-OracleCount -tableName $table
            $postgresCount = Get-PostgresCount -tableName $table
            
            if (-not $oracleCount -or -not $postgresCount) {
                Write-Host ("{0,-40} {1,15} {2,15} {3,10}" -f $table, "ERROR", "ERROR", "ERROR") -ForegroundColor Red
                $errors++
            } elseif ($oracleCount -eq $postgresCount) {
                Write-Host ("{0,-40} {1,15} {2,15} {3,10}" -f $table, $oracleCount, $postgresCount, "OK") -ForegroundColor Green
                $matched++
            } else {
                Write-Host ("{0,-40} {1,15} {2,15} {3,10}" -f $table, $oracleCount, $postgresCount, "MISMATCH") -ForegroundColor Red
                $mismatched++
            }
        } catch {
            Write-Host ("{0,-40} {1,15} {2,15} {3,10}" -f $table, "ERROR", "ERROR", "ERROR") -ForegroundColor Red
            $errors++
        }
    } else {
        Write-Host ("{0,-40} {1,15} {2,15} {3,10}" -f $table, "N/A", "MISSING", "MISSING") -ForegroundColor Red
        $missing++
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Validation Summary" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Matched: $matched tables" -ForegroundColor Green
if ($mismatched -gt 0) {
    Write-Host "Mismatched: $mismatched tables" -ForegroundColor Red
}
if ($missing -gt 0) {
    Write-Host "Missing in PostgreSQL: $missing tables" -ForegroundColor Red
}
if ($errors -gt 0) {
    Write-Host "Errors: $errors tables" -ForegroundColor Red
}
Write-Host ""

# Sample data comparison (optional)
if ($mismatched -gt 0 -or $missing -gt 0) {
    Write-Host "Some tables have issues. Check the details above." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To investigate further:"
    Write-Host "  1. Check migration logs in migrate-data\logs\"
    Write-Host "  2. Compare sample data manually"
    Write-Host "  3. Check for data type conversion issues"
}

if ($matched -eq $tableCount -and $mismatched -eq 0 -and $missing -eq 0 -and $errors -eq 0) {
    Write-Host "All tables validated successfully!" -ForegroundColor Green
}

Write-Host ""
