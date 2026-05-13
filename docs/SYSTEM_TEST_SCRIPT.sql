-- ═══════════════════════════════════════════════════════════════════════════
-- SYSTEM TEST SCRIPT - Registration to Queue Ticket Flow
-- ═══════════════════════════════════════════════════════════════════════════
-- Purpose: Verify all database functions and schema are correct
-- Run this after applying all migrations
-- ═══════════════════════════════════════════════════════════════════════════

\echo '═══════════════════════════════════════════════════════════════════════════'
\echo 'SYSTEM TEST SCRIPT - Starting Tests'
\echo '═══════════════════════════════════════════════════════════════════════════'
\echo ''

-- ───────────────────────────────────────────────────────────────────────────
-- Test 1: Verify Table Structures
-- ───────────────────────────────────────────────────────────────────────────

\echo 'Test 1: Verifying table structures...'
\echo ''

\echo '  Citizens table:'
\d public.citizens

\echo ''
\echo '  Queue tickets table:'
\d public.queue_tickets

\echo ''

-- ───────────────────────────────────────────────────────────────────────────
-- Test 2: Verify Validation Functions Exist
-- ───────────────────────────────────────────────────────────────────────────

\echo 'Test 2: Checking validation functions...'
\echo ''

SELECT 
    routine_name,
    routine_type,
    data_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
      'validate_text_input',
      'validate_required_text',
      'validate_email',
      'validate_phone_number',
      'sanitize_text_columns'
  )
ORDER BY routine_name;

\echo ''

-- ───────────────────────────────────────────────────────────────────────────
-- Test 3: Test Validation Functions
-- ───────────────────────────────────────────────────────────────────────────

\echo 'Test 3: Testing validation functions...'
\echo ''

\echo '  Test 3a: validate_text_input with whitespace'
SELECT validate_text_input('  Hello   World  ') AS result;
-- Expected: 'Hello World'

\echo ''
\echo '  Test 3b: validate_text_input with whitespace only'
SELECT validate_text_input('   ') AS result;
-- Expected: NULL

\echo ''
\echo '  Test 3c: validate_email with uppercase'
SELECT validate_email('USER@EXAMPLE.COM') AS result;
-- Expected: 'user@example.com'

\echo ''
\echo '  Test 3d: validate_phone_number'
SELECT validate_phone_number('9171234567') AS result;
-- Expected: '+639171234567'

\echo ''

-- ───────────────────────────────────────────────────────────────────────────
-- Test 4: Verify Queue Functions Exist
-- ───────────────────────────────────────────────────────────────────────────

\echo 'Test 4: Checking queue-related functions...'
\echo ''

SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
      'create_queue_ticket',
      'get_queue_limiter_status',
      'is_daily_ticket_limit_reached',
      'get_today_ticket_count',
      'get_daily_ticket_limit',
      'is_queue_limiter_enabled'
  )
ORDER BY routine_name;

\echo ''

-- ───────────────────────────────────────────────────────────────────────────
-- Test 5: Verify create_queue_ticket Function Signature
-- ───────────────────────────────────────────────────────────────────────────

\echo 'Test 5: Checking create_queue_ticket function signature...'
\echo ''

\df create_queue_ticket

\echo ''

-- ───────────────────────────────────────────────────────────────────────────
-- Test 6: Test Queue Limiter Status
-- ───────────────────────────────────────────────────────────────────────────

\echo 'Test 6: Testing queue limiter status...'
\echo ''

SELECT * FROM get_queue_limiter_status();

\echo ''

-- ───────────────────────────────────────────────────────────────────────────
-- Test 7: Verify Triggers
-- ───────────────────────────────────────────────────────────────────────────

\echo 'Test 7: Checking auto-sanitization triggers...'
\echo ''

SELECT 
    trigger_name,
    event_object_table,
    action_timing,
    event_manipulation
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND trigger_name LIKE '%sanitize%'
ORDER BY event_object_table, trigger_name;

\echo ''

-- ───────────────────────────────────────────────────────────────────────────
-- Test 8: Verify Check Constraints
-- ───────────────────────────────────────────────────────────────────────────

\echo 'Test 8: Checking table constraints...'
\echo ''

SELECT 
    table_name,
    constraint_name,
    constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'public'
  AND table_name IN ('citizens', 'queue_tickets', 'staff')
  AND constraint_type = 'CHECK'
ORDER BY table_name, constraint_name;

\echo ''

-- ───────────────────────────────────────────────────────────────────────────
-- Test 9: Verify System Config Table
-- ───────────────────────────────────────────────────────────────────────────

\echo 'Test 9: Checking system configuration...'
\echo ''

SELECT 
    config_key,
    config_value,
    description
FROM public.system_config
ORDER BY config_key;

\echo ''

-- ───────────────────────────────────────────────────────────────────────────
-- Test 10: Verify RLS Policies
-- ───────────────────────────────────────────────────────────────────────────

\echo 'Test 10: Checking Row Level Security policies...'
\echo ''

SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('citizens', 'queue_tickets', 'system_config')
ORDER BY tablename, policyname;

\echo ''

-- ───────────────────────────────────────────────────────────────────────────
-- Test 11: Check for Orphaned Functions
-- ───────────────────────────────────────────────────────────────────────────

\echo 'Test 11: Checking for duplicate or orphaned functions...'
\echo ''

SELECT 
    routine_name,
    COUNT(*) as version_count
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN ('create_queue_ticket')
GROUP BY routine_name
HAVING COUNT(*) > 1;

\echo ''
\echo '  (Empty result means no duplicates - this is good!)'
\echo ''

-- ───────────────────────────────────────────────────────────────────────────
-- Test 12: Verify Data Type Consistency
-- ───────────────────────────────────────────────────────────────────────────

\echo 'Test 12: Verifying data type consistency...'
\echo ''

\echo '  Citizens.id type:'
SELECT 
    column_name,
    data_type,
    character_maximum_length
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'citizens'
  AND column_name = 'id';

\echo ''
\echo '  Queue_tickets.citizen_id type:'
SELECT 
    column_name,
    data_type,
    character_maximum_length
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'queue_tickets'
  AND column_name = 'citizen_id';

\echo ''

-- ───────────────────────────────────────────────────────────────────────────
-- Summary
-- ───────────────────────────────────────────────────────────────────────────

\echo '═══════════════════════════════════════════════════════════════════════════'
\echo 'SYSTEM TEST SCRIPT - Tests Complete'
\echo '═══════════════════════════════════════════════════════════════════════════'
\echo ''
\echo 'Review the output above to verify:'
\echo '  ✓ All tables exist with correct structure'
\echo '  ✓ All validation functions exist'
\echo '  ✓ Validation functions work correctly'
\echo '  ✓ Queue functions exist'
\echo '  ✓ create_queue_ticket has correct signature (citizen_id should be BIGINT)'
\echo '  ✓ Queue limiter is configured'
\echo '  ✓ Triggers are in place'
\echo '  ✓ Check constraints exist'
\echo '  ✓ System config is populated'
\echo '  ✓ RLS policies are active'
\echo '  ✓ No duplicate functions'
\echo '  ✓ Data types are consistent (citizens.id and queue_tickets.citizen_id both BIGINT)'
\echo ''
\echo 'If all checks pass, the system is ready for testing!'
\echo ''
