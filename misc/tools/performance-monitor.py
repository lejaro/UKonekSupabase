#!/usr/bin/env python3
"""
Automated Supabase Performance Monitor
Monitors database performance metrics and alerts on issues
"""

import subprocess
import json
import datetime
import os
import sys
from typing import Dict, List, Optional

class SupabasePerformanceMonitor:
    def __init__(self, project_ref: str, output_dir: str = "./reports"):
        self.project_ref = project_ref
        self.output_dir = output_dir
        self.timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Ensure output directory exists
        os.makedirs(output_dir, exist_ok=True)
    
    def run_supabase_command(self, command: List[str]) -> Optional[str]:
        """Execute Supabase CLI command and return output"""
        try:
            result = subprocess.run(
                ["supabase"] + command, 
                capture_output=True, 
                text=True, 
                check=True
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            print(f"Error running supabase command: {e}")
            print(f"stderr: {e.stderr}")
            return None
    
    def check_database_connectivity(self) -> bool:
        """Check if we can connect to the database"""
        output = self.run_supabase_command(["status"])
        return output is not None and "Running" in output
    
    def get_migration_status(self) -> Dict:
        """Get current migration status"""
        output = self.run_supabase_command(["migration", "list"])
        if not output:
            return {"status": "error", "migrations": []}
        
        migrations = []
        lines = output.strip().split('\n')
        for line in lines[1:]:  # Skip header
            if line.strip():
                parts = line.split()
                if len(parts) >= 2:
                    migrations.append({
                        "name": parts[0],
                        "status": "applied" if "✓" in line else "pending"
                    })
        
        return {
            "status": "success",
            "migrations": migrations,
            "total": len(migrations),
            "pending": len([m for m in migrations if m["status"] == "pending"])
        }
    
    def analyze_recent_logs(self) -> Dict:
        """Analyze recent function logs for errors"""
        output = self.run_supabase_command(["functions", "logs", "--limit", "100"])
        if not output:
            return {"status": "error", "errors": 0, "warnings": 0}
        
        errors = output.lower().count("error")
        warnings = output.lower().count("warning") + output.lower().count("warn")
        
        return {
            "status": "success",
            "errors": errors,
            "warnings": warnings,
            "sample_logs": output[:500] + "..." if len(output) > 500 else output
        }
    
    def generate_optimization_migration(self, recommendations: List[str]) -> str:
        """Generate a new migration file with performance optimizations"""
        migration_name = f"performance_optimization_{self.timestamp}"
        migration_content = f"""-- Performance Optimization Migration
-- Generated on: {datetime.datetime.now()}
-- Based on performance analysis recommendations

-- =============================================================================
-- PERFORMANCE OPTIMIZATIONS
-- =============================================================================

"""
        
        for i, rec in enumerate(recommendations, 1):
            migration_content += f"-- {i}. {rec}\n"
            
            # Generate SQL based on recommendation type
            if "index" in rec.lower():
                migration_content += f"-- TODO: Add specific CREATE INDEX statements\n"
            elif "vacuum" in rec.lower():
                migration_content += f"-- TODO: Consider VACUUM ANALYZE for bloated tables\n"
            elif "rls" in rec.lower():
                migration_content += f"-- TODO: Review RLS policies for performance\n"
            
            migration_content += "\n"
        
        migration_content += """
-- =============================================================================
-- MONITORING SETUP
-- =============================================================================

-- Enable pg_stat_statements for query monitoring (if not already enabled)
-- This requires superuser privileges - run in Supabase dashboard
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Create performance monitoring view
CREATE OR REPLACE VIEW public.performance_summary AS
SELECT 
    'table_count' as metric,
    count(*)::text as value
FROM pg_stat_user_tables
UNION ALL
SELECT 
    'unused_indexes' as metric,
    count(*)::text as value
FROM pg_stat_user_indexes 
WHERE idx_scan = 0;

-- Grant access to monitoring view
GRANT SELECT ON public.performance_summary TO authenticated;
"""
        
        migration_path = f"./supabase/migrations/{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}_{migration_name}.sql"
        
        with open(migration_path, 'w') as f:
            f.write(migration_content)
        
        return migration_path
    
    def run_performance_check(self) -> Dict:
        """Run comprehensive performance check"""
        print("🔍 Running Supabase Performance Check...")
        
        report = {
            "timestamp": datetime.datetime.now().isoformat(),
            "project_ref": self.project_ref,
            "checks": {}
        }
        
        # 1. Database connectivity
        print("  • Checking database connectivity...")
        report["checks"]["connectivity"] = {
            "status": "healthy" if self.check_database_connectivity() else "error"
        }
        
        # 2. Migration status
        print("  • Checking migration status...")
        report["checks"]["migrations"] = self.get_migration_status()
        
        # 3. Function logs analysis
        print("  • Analyzing recent logs...")
        report["checks"]["logs"] = self.analyze_recent_logs()
        
        # 4. Generate recommendations
        print("  • Generating recommendations...")
        recommendations = self.generate_recommendations(report)
        report["recommendations"] = recommendations
        
        # 5. Create optimization migration if needed
        if recommendations["high_priority"]:
            print("  • Creating optimization migration...")
            migration_path = self.generate_optimization_migration(
                recommendations["high_priority"]
            )
            report["optimization_migration"] = migration_path
        
        # Save report
        report_path = f"{self.output_dir}/performance_report_{self.timestamp}.json"
        with open(report_path, 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"✅ Performance report saved: {report_path}")
        return report
    
    def generate_recommendations(self, report: Dict) -> Dict:
        """Generate performance recommendations based on analysis"""
        recommendations = {
            "high_priority": [],
            "medium_priority": [],
            "low_priority": []
        }
        
        # Check migration status
        migrations = report["checks"]["migrations"]
        if migrations["pending"] > 0:
            recommendations["high_priority"].append(
                f"Apply {migrations['pending']} pending migrations"
            )
        
        # Check log errors
        logs = report["checks"]["logs"]
        if logs["errors"] > 10:
            recommendations["high_priority"].append(
                "High error rate detected in function logs - investigate immediately"
            )
        elif logs["errors"] > 0:
            recommendations["medium_priority"].append(
                f"Monitor function errors: {logs['errors']} errors found"
            )
        
        # Generic performance recommendations
        recommendations["medium_priority"].extend([
            "Run database performance analysis queries",
            "Review and optimize RLS policies",
            "Check for unused indexes",
            "Monitor table bloat and vacuum status"
        ])
        
        return recommendations
    
    def setup_monitoring_schedule(self):
        """Setup automated monitoring schedule"""
        cron_command = f"""
# Supabase Performance Monitoring - Add to crontab
# Run every hour during business hours
0 9-17 * * 1-5 cd {os.getcwd()} && python3 tools/performance-monitor.py
"""
        
        schedule_file = f"{self.output_dir}/monitoring_schedule.txt"
        with open(schedule_file, 'w') as f:
            f.write(cron_command)
        
        print(f"📅 Monitoring schedule saved to: {schedule_file}")
        print("To activate, run: crontab -e and add the contents of this file")


def main():
    """Main execution function"""
    if len(sys.argv) < 2:
        print("Usage: python3 performance-monitor.py <project_ref> [output_dir]")
        print("Example: python3 performance-monitor.py dqjxpwbsbzagbjtulhue ./reports")
        sys.exit(1)
    
    project_ref = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else "./reports"
    
    monitor = SupabasePerformanceMonitor(project_ref, output_dir)
    
    # Run performance check
    report = monitor.run_performance_check()
    
    # Display summary
    print("\n📋 PERFORMANCE SUMMARY:")
    print(f"   Connectivity: {report['checks']['connectivity']['status']}")
    print(f"   Pending Migrations: {report['checks']['migrations']['pending']}")
    print(f"   Recent Errors: {report['checks']['logs']['errors']}")
    print(f"   Recent Warnings: {report['checks']['logs']['warnings']}")
    
    # Display recommendations
    if report["recommendations"]["high_priority"]:
        print("\n🚨 HIGH PRIORITY ACTIONS:")
        for rec in report["recommendations"]["high_priority"]:
            print(f"   • {rec}")
    
    if report["recommendations"]["medium_priority"]:
        print("\n📋 MEDIUM PRIORITY ACTIONS:")
        for rec in report["recommendations"]["medium_priority"]:
            print(f"   • {rec}")
    
    # Setup monitoring if requested
    if "--setup-monitoring" in sys.argv:
        monitor.setup_monitoring_schedule()


if __name__ == "__main__":
    main()