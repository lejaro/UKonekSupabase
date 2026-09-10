const fs = require('fs');
const path = require('path');
const https = require('https');

const token = process.env.SUPABASE_ACCESS_TOKEN || '';
const projectRef = process.env.SUPABASE_PROJECT_REF || 'dqjxpwbsbzagbjtulhue';

function runSqlOnce(sql) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify({ query: sql });
    const options = {
      hostname: 'api.supabase.com',
      port: 443,
      path: `/v1/projects/${projectRef}/database/query`,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data)
      }
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(body) });
        } catch (e) {
          resolve({ status: res.statusCode, body });
        }
      });
    });

    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function runSql(sql, retries = 3) {
  for (let i = 0; i < retries; i++) {
    try {
      return await runSqlOnce(sql);
    } catch (err) {
      if (i === retries - 1) throw err;
      console.log(`Network retry (${i + 1}/${retries})...`);
      await new Promise(r => setTimeout(r, 1500));
    }
  }
}

async function main() {
  console.log('Fetching applied migrations from supabase_migrations.schema_migrations...');
  const appliedRes = await runSql('SELECT version FROM supabase_migrations.schema_migrations ORDER BY version ASC;');
  if (appliedRes.status !== 200 && appliedRes.status !== 201) {
    console.error('Failed to fetch schema_migrations:', appliedRes);
    process.exit(1);
  }

  const appliedVersions = new Set(appliedRes.data.map(row => row.version));
  console.log(`Found ${appliedVersions.size} already-applied migrations on remote database.`);

  const migrationsDir = path.join(__dirname, 'migrations');
  const files = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort();

  for (const file of files) {
    const versionMatch = file.match(/^(\d+)/);
    if (!versionMatch) continue;
    const version = versionMatch[1];

    if (appliedVersions.has(version)) {
      continue;
    }

    console.log(`\n========================================`);
    console.log(`Applying migration: ${file} (version: ${version})...`);
    const filePath = path.join(migrationsDir, file);
    const sql = fs.readFileSync(filePath, 'utf8');

    const execRes = await runSql(sql);
    if (execRes.status !== 200 && execRes.status !== 201) {
      console.error(`ERROR applying migration ${file}:`, JSON.stringify(execRes, null, 2));
      process.exit(1);
    }
    console.log(`Migration ${file} executed successfully.`);

    // Record into schema_migrations
    const recordSql = `INSERT INTO supabase_migrations.schema_migrations (version) VALUES ('${version}') ON CONFLICT (version) DO NOTHING;`;
    const recRes = await runSql(recordSql);
    if (recRes.status !== 200 && recRes.status !== 201) {
      console.error(`Warning: could not record version ${version}:`, recRes);
    } else {
      console.log(`Recorded version ${version} into supabase_migrations.schema_migrations.`);
    }
  }

  console.log('\nAll pending migrations pushed and applied successfully to Supabase DB!');
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
