-- =============================================================================
-- Supabase Performance Analysis Queries
-- Run these in your Supabase Dashboard > SQL Editor
-- =============================================================================

-- 1. DATABASE OVERVIEW
-- Get overall database size and activity
SELECT 
    'Database Size' as metric,
    pg_size_pretty(pg_database_size(current_database())) as value
UNION ALL
SELECT 
    'Active Connections' as metric,
    count(*)::text as value
FROM pg_stat_activity 
WHERE state = 'active'
UNION ALL  
SELECT 
    'Tables Count' as metric,
    count(*)::text as value
FROM information_schema.tables 
WHERE table_schema = 'public';

-- 2. TABLE SIZE ANALYSIS
-- Find largest tables and their growth patterns
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) as index_size,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_live_tup as live_rows,
    n_dead_tup as dead_rows,
    CASE 
        WHEN n_live_tup > 0 THEN round((n_dead_tup::float / n_live_tup::float) * 100, 2)
        ELSE 0
    END as dead_row_percent
FROM pg_stat_user_tables 
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- 3. INDEX USAGE ANALYSIS
-- Find unused or underused indexes
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    CASE 
        WHEN idx_scan = 0 THEN '🔴 UNUSED - Consider dropping'
        WHEN idx_scan < 10 THEN '🟡 LOW USAGE - Review necessity' 
        WHEN idx_scan < 100 THEN '🟢 MODERATE USAGE'
        ELSE '🟢 HIGH USAGE'
    END as usage_status
FROM pg_stat_user_indexes 
ORDER BY idx_scan ASC, pg_relation_size(indexrelid) DESC;

-- 4. QUERY PERFORMANCE PATTERNS
-- Analyze table access patterns
SELECT 
    schemaname,
    tablename,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    CASE 
        WHEN seq_scan > 0 AND idx_scan > 0 THEN 
            round((seq_scan::float / (seq_scan + idx_scan)::float) * 100, 2)
        WHEN seq_scan > 0 THEN 100
        ELSE 0
    END as seq_scan_percent,
    CASE 
        WHEN seq_scan > idx_scan AND seq_tup_read > 10000 THEN '🔴 HIGH sequential scans - needs indexes'
        WHEN seq_scan > 0 AND seq_tup_read > 1000 THEN '🟡 Some sequential scans'
        ELSE '🟢 Good index usage'
    END as recommendation
FROM pg_stat_user_tables 
WHERE (seq_scan + idx_scan) > 0
ORDER BY seq_scan DESC, seq_tup_read DESC;

-- 5. BLOAT ANALYSIS
-- Identify tables that need VACUUM or have excessive bloat
SELECT 
    schemaname,
    tablename,
    n_dead_tup,
    n_live_tup,
    CASE 
        WHEN n_live_tup > 0 THEN round((n_dead_tup::float / n_live_tup::float) * 100, 2)
        ELSE 0
    END as bloat_percent,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    CASE 
        WHEN n_dead_tup > n_live_tup * 0.2 THEN '🔴 High bloat - manual VACUUM needed'
        WHEN n_dead_tup > n_live_tup * 0.1 THEN '🟡 Moderate bloat - monitor'
        ELSE '🟢 Healthy'
    END as bloat_status
FROM pg_stat_user_tables 
ORDER BY bloat_percent DESC;

-- 6. RLS POLICY PERFORMANCE
-- Check for policies that might cause performance issues
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE schemaname = 'public'
ORDER BY tablename;

-- 7. FOREIGN KEY RELATIONSHIPS
-- Analyze FK relationships and potential join performance
SELECT 
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    tc.constraint_name
FROM information_schema.table_constraints AS tc 
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY' 
    AND tc.table_schema = 'public'
ORDER BY tc.table_name;

-- 8. MISSING INDEX SUGGESTIONS
-- Suggest indexes based on foreign keys without indexes
WITH fk_columns AS (
    SELECT 
        tc.table_name,
        kcu.column_name
    FROM information_schema.table_constraints AS tc 
    JOIN information_schema.key_column_usage AS kcu
        ON tc.constraint_name = kcu.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY' 
        AND tc.table_schema = 'public'
),
existing_indexes AS (
    SELECT 
        t.relname AS table_name,
        a.attname AS column_name
    FROM pg_index i
    JOIN pg_class t ON t.oid = i.indrelid
    JOIN pg_attribute a ON a.attrelid = t.oid 
        AND a.attnum = ANY(i.indkey)
    WHERE t.relkind = 'r'
        AND a.attnum > 0
)
SELECT 
    'CREATE INDEX IF NOT EXISTS idx_' || fk.table_name || '_' || fk.column_name || 
    ' ON public.' || fk.table_name || '(' || fk.column_name || ');' AS suggested_index
FROM fk_columns fk
LEFT JOIN existing_indexes ei ON ei.table_name = fk.table_name AND ei.column_name = fk.column_name
WHERE ei.column_name IS NULL;

-- 9. PERFORMANCE SUMMARY
-- Overall database health summary
SELECT 
    'Performance Summary' as section,
    json_build_object(
        'total_tables', (SELECT count(*) FROM pg_stat_user_tables),
        'total_indexes', (SELECT count(*) FROM pg_stat_user_indexes),
        'unused_indexes', (SELECT count(*) FROM pg_stat_user_indexes WHERE idx_scan = 0),
        'high_bloat_tables', (SELECT count(*) FROM pg_stat_user_tables WHERE n_dead_tup > n_live_tup * 0.2),
        'tables_needing_indexes', (
            SELECT count(*) FROM pg_stat_user_tables 
            WHERE seq_scan > idx_scan AND seq_tup_read > 10000
        )
    ) as metrics;