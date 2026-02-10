import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

loadEnvFile(path.resolve(__dirname, '../.env'));

const token = process.env.TESLA_USER_ACCESS_TOKEN || process.env.TESLA_ACCESS_TOKEN || '';
const base = process.env.TESLA_FLEET_API_BASE || 'https://fleet-api.prd.na.vn.cloud.tesla.com';

if (!token) {
  console.error('[check] Missing Tesla user access token.');
  console.error('[check] Next steps:');
  console.error('  1) Set TESLA_CLIENT_ID / TESLA_CLIENT_SECRET / TESLA_REDIRECT_URI in .env');
  console.error('  2) Run: npm run tesla:oauth:start');
  console.error('  3) After login redirect, run: npm run tesla:oauth:exchange -- <code>');
  process.exit(1);
}

try {
  const res = await fetch(`${base}/api/1/vehicles`, {
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json'
    }
  });

  const text = await res.text();
  let parsed;
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch {
    parsed = { raw: text };
  }

  if (!res.ok) {
    const msg = parsed?.error || parsed?.message || text || `HTTP ${res.status}`;
    console.error(`[check] Fleet API failed: ${msg}`);
    process.exit(2);
  }

  const vehicles = Array.isArray(parsed?.response) ? parsed.response : [];
  console.log(`[check] OK. Vehicles found: ${vehicles.length}`);

  for (const [index, vehicle] of vehicles.entries()) {
    const vin = String(vehicle?.vin || '');
    const maskedVin = vin.length >= 6 ? `${vin.slice(0, 3)}...${vin.slice(-3)}` : vin || '(none)';
    const name = vehicle?.display_name || '(no display_name)';
    const state = vehicle?.state || 'unknown';
    console.log(`  ${index + 1}. ${name} | ${maskedVin} | ${state}`);
  }

  process.exit(0);
} catch (error) {
  console.error('[check] Network error:', error instanceof Error ? error.message : error);
  process.exit(3);
}

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return;
  }

  const raw = fs.readFileSync(filePath, 'utf8');
  const lines = raw.split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }

    const idx = trimmed.indexOf('=');
    if (idx < 0) {
      continue;
    }

    const key = trimmed.slice(0, idx).trim();
    const value = trimmed.slice(idx + 1).trim().replace(/^['"]|['"]$/g, '');
    if (!key) {
      continue;
    }

    if (process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}
