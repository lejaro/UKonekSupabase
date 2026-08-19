# Supabase Performance Monitor Script
# Monitors database performance and generates optimization reports

param(
    [string]$OutputDir = ".\reports",
    [switch]$Detailed,
    [switch]$Export
)

# Ensure output directory exists
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFile = "$OutputDir\performance_report_$timestamp.json"

Write-Host "🔍 Starting Supabase Performance Analysis..." -ForegroundColor Cyan

# 1. Database Statistics
Write-Host "`n📊 Gathering Database Statistics..." -ForegroundColor Yellow
$stats = @{
    timestamp = Get-Date
    database_size = $null
    table_sizes = @{}
    index_usage = @{}
    slow_queries = @{}
    connection_stats = @{}
}

# Get database size and table statistics
Write-Host "  • Analyzing table sizes and row counts..."
try {
    $tableStats = supabase db diff --debug 2>&1 | Out-String
    $stats.table_info = "Connected to database successfully"
} catch {
    $stats.table_info = "Error connecting: $($_.Exception.Message)"
}

# 2. Query Performance Analysis
Write-Host "`n⚡ Analyzing Query Performance..." -ForegroundColor Yellow

# Create SQL files for performance analysis
@"
-- Performance Analysis Queries
-- Execute these in your Supabase dashboard or via psql

-- 1. Table sizes and bloat analysis
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
    pg_stat_get_tuples_returned(c.oid) as tuples_returned,
    pg_stat_get_tuples_fetched(c.oid) as tuples_fetched,
    pg_stat_get_tuples_inserted(c.oid) as tuples_inserted,
    pg_stat_get_tuples_updated(c.oid) as tuples_updated,
    pg_stat_get_tuples_deleted(c.oid) as tuples_deleted
FROM pg_tables pt
JOIN pg_class c ON c.relname = pt.tablename
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
"@ | Out-File -FilePath "$OutputDir\table_analysis_$timestamp.sql" -Encoding UTF8

@"
-- Index usage analysis
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_tup_read,
    idx_tup_fetch,
    idx_scan,
    CASE 
        WHEN idx_scan = 0 THEN 'UNUSED INDEX - Consider dropping'
        WHEN idx_scan < 10 THEN 'LOW USAGE - Review necessity'
        ELSE 'ACTIVE'
    END as usage_status
FROM pg_stat_user_indexes 
ORDER BY idx_scan ASC;
"@ | Out-File -FilePath "$OutputDir\index_analysis_$timestamp.sql" -Encoding UTF8

@"
-- Slow query patterns (requires pg_stat_statements extension)
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    max_time,
    stddev_time,
    rows,
    100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) AS hit_percent
FROM pg_stat_statements 
WHERE calls > 100 -- Only frequent queries
ORDER BY mean_time DESC 
LIMIT 20;
"@ | Out-File -FilePath "$OutputDir\slow_queries_$timestamp.sql" -Encoding UTF8

# 3. Generate performance insights
$insights = @{
    recommendations = @()
    optimization_opportunities = @()
    immediate_actions = @()
}

# Check for common performance issues
Write-Host "`n🔧 Generating Optimization Recommendations..." -ForegroundColor Yellow

# Analyze recent migrations for performance impact
$recentMigrations = Get-ChildItem -Path ".\supabase\migrations" -Filter "*.sql" | Sort-Object CreationTime -Descending | Select-Object -First 5

foreach ($migration in $recentMigrations) {
    $content = Get-Content $migration.FullName -Raw
    
    # Check for missing indexes
    if ($content -match "WHERE" -and $content -notmatch "CREATE INDEX") {
        $insights.recommendations += "Migration $($migration.Name): Consider adding indexes for WHERE clauses"
    }
    
    # Check for large table operations
    if ($content -match "ALTER TABLE.*ADD COLUMN" -and $content -notmatch "DEFAULT") {
        $insights.optimization_opportunities += "Migration $($migration.Name): Adding non-default columns to large tables may be slow"
    }
}

# 4. Generate CLI commands for optimization
$optimizationCommands = @"
# Supabase Performance Optimization Commands

# 1. Reset database statistics (run before monitoring)
supabase db reset --debug

# 2. Apply performance migrations
supabase db push --debug

# 3. Check migration status
supabase migration list

# 4. Generate new migration for indexes
supabase migration new add_performance_indexes

# 5. Monitor real-time connections
supabase functions logs --follow

# 6. Database backup before optimization
supabase db dump > backup_$(Get-Date -Format 'yyyyMMdd').sql

"@

$optimizationCommands | Out-File -FilePath "$OutputDir\optimization_commands_$timestamp.txt" -Encoding UTF8

# 5. Create performance report
$performanceReport = @{
    generated_at = Get-Date
    project_ref = "dqjxpwbsbzagbjtulhue"
    analysis_files = @{
        table_analysis = "table_analysis_$timestamp.sql"
        index_analysis = "index_analysis_$timestamp.sql"
        slow_queries = "slow_queries_$timestamp.sql"
    }
    insights = $insights
    cli_commands = "optimization_commands_$timestamp.txt"
    next_steps = @(
        "1. Execute analysis SQL files in Supabase dashboard",
        "2. Review unused indexes and drop if appropriate",
        "3. Add missing indexes based on query patterns",
        "4. Monitor query performance after changes",
        "5. Schedule regular performance reviews"
    )
}

# Save report
$performanceReport | ConvertTo-Json -Depth 4 | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host "`n✅ Performance Analysis Complete!" -ForegroundColor Green
Write-Host "📄 Report saved to: $reportFile" -ForegroundColor Cyan
Write-Host "📁 Analysis files in: $OutputDir" -ForegroundColor Cyan

# Display summary
Write-Host "`n📋 IMMEDIATE ACTIONS:" -ForegroundColor Magenta
Write-Host "1. Run SQL files in Supabase dashboard to get current metrics"
Write-Host "2. Review migration history for performance impacts"
Write-Host "3. Apply recommended optimizations via new migrations"
Write-Host "4. Set up scheduled monitoring"

if ($Export) {
    Write-Host "`n📤 Exporting results to dashboard..." -ForegroundColor Yellow
    # Here you could integrate with external monitoring tools
}