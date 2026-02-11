import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { loadEnvFile, upsertEnvFile } from './env.mjs';
import { maskToken } from './tesla_oauth_common.mjs';
import { syncTokensToTeslaMateRuntime } from './teslamate_token_bridge.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootEnv = path.resolve(__dirname, '../.env');

loadEnvFile(rootEnv);

const clientId = String(process.env.TESLA_CLIENT_ID || '').trim();
const clientSecret = String(process.env.TESLA_CLIENT_SECRET || '').trim();
const refreshToken = String(process.env.TESLA_USER_REFRESH_TOKEN || '').trim();
const tokenUrl = String(process.env.TESLA_TOKEN_URL || 'https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token').trim();
const containerName = String(process.env.TESLAMATE_CONTAINER_NAME || 'teslamate-stack-teslamate-1').trim();
const syncOnRefresh = process.env.TESLAMATE_SYNC_ON_REFRESH !== '0';

if (!clientId || !refreshToken) {
  console.error('[oauth:refresh:sync] Missing TESLA_CLIENT_ID or TESLA_USER_REFRESH_TOKEN in .env');
  process.exit(1);
}

const body = new URLSearchParams();
body.set('grant_type', 'refresh_token');
body.set('client_id', clientId);
body.set('refresh_token', refreshToken);
if (clientSecret) {
  body.set('client_secret', clientSecret);
}

const res = await fetch(tokenUrl, {
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body
});

const text = await res.text();
let parsed;
try {
  parsed = text ? JSON.parse(text) : {};
} catch {
  parsed = { raw: text };
}

if (!res.ok) {
  const message = parsed?.error_description || parsed?.error || text || `HTTP ${res.status}`;
  console.error(`[oauth:refresh:sync] Refresh failed (${res.status}): ${message}`);
  process.exit(2);
}

const accessToken = String(parsed?.access_token || '').trim();
const nextRefreshToken = String(parsed?.refresh_token || refreshToken).trim();
const expiresIn = Number(parsed?.expires_in || 0);
const expiresAt = expiresIn > 0 ? new Date(Date.now() + expiresIn * 1000).toISOString() : '';

if (!accessToken) {
  console.error('[oauth:refresh:sync] Missing access_token in refresh response.');
  process.exit(3);
}

upsertEnvFile(rootEnv, {
  TESLA_USER_ACCESS_TOKEN: accessToken,
  TESLA_USER_REFRESH_TOKEN: nextRefreshToken,
  TESLA_USER_TOKEN_EXPIRES_AT: expiresAt
});

console.log('[oauth:refresh:sync] Refresh OK. Saved updated tokens to .env');
console.log(`[oauth:refresh:sync] access_token=${maskToken(accessToken)}`);
console.log(`[oauth:refresh:sync] refresh_token=${maskToken(nextRefreshToken)}`);
if (expiresAt) {
  console.log(`[oauth:refresh:sync] expires_at=${expiresAt}`);
}

if (!syncOnRefresh) {
  console.log('[oauth:refresh:sync] TESLAMATE_SYNC_ON_REFRESH=0, skip TeslaMate runtime sync.');
  process.exit(0);
}

try {
  const sync = syncTokensToTeslaMateRuntime({
    accessToken,
    refreshToken: nextRefreshToken,
    containerName
  });
  console.log(`[oauth:refresh:sync] TeslaMate runtime sync OK (container=${containerName})`);
  if (sync.stdout) {
    console.log('[oauth:refresh:sync] docker rpc output:');
    console.log(sync.stdout);
  }
} catch (error) {
  console.error('[oauth:refresh:sync] TeslaMate runtime sync failed.');
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(4);
}
