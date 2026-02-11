import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { loadEnvFile, upsertEnvFile } from './env.mjs';
import { exchangeAuthorizationCode, maskToken } from './tesla_oauth_common.mjs';
import { syncTokensToTeslaMateRuntime } from './teslamate_token_bridge.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootEnv = path.resolve(__dirname, '../.env');

loadEnvFile(rootEnv);

const codeInput = process.argv[2] || '';
const clientId = process.env.TESLA_CLIENT_ID || '';
const clientSecret = process.env.TESLA_CLIENT_SECRET || '';
const redirectUri = process.env.TESLA_REDIRECT_URI || '';
const codeVerifier = process.env.TESLA_CODE_VERIFIER || '';
const audience = process.env.TESLA_AUDIENCE || process.env.TESLA_FLEET_API_BASE || 'https://fleet-api.prd.na.vn.cloud.tesla.com';
const containerName = process.env.TESLAMATE_CONTAINER_NAME || 'teslamate-stack-teslamate-1';
const syncOnExchange = process.env.TESLAMATE_SYNC_ON_EXCHANGE !== '0';

if (!codeInput) {
  console.error(
    '[oauth:exchange:sync] Missing argument. Usage: node backend/tesla_oauth_exchange_and_sync.mjs <code-or-callback-url>'
  );
  process.exit(1);
}

if (!clientId || !clientSecret || !redirectUri) {
  console.error('[oauth:exchange:sync] Missing TESLA_CLIENT_ID / TESLA_CLIENT_SECRET / TESLA_REDIRECT_URI in .env');
  process.exit(1);
}

if (!codeVerifier) {
  console.error('[oauth:exchange:sync] Missing TESLA_CODE_VERIFIER in .env. Run npm run tesla:oauth:start first.');
  process.exit(1);
}

let exchanged;
try {
  exchanged = await exchangeAuthorizationCode({
    codeInput,
    clientId,
    clientSecret,
    redirectUri,
    codeVerifier,
    audience
  });
} catch (error) {
  console.error('[oauth:exchange:sync]', error instanceof Error ? error.message : 'Token exchange failed.');
  process.exit(2);
}

const accessToken = exchanged.accessToken;
const refreshToken = exchanged.refreshToken;
const expiresAt = exchanged.expiresAt;

upsertEnvFile(rootEnv, {
  TESLA_USER_ACCESS_TOKEN: accessToken,
  TESLA_USER_REFRESH_TOKEN: refreshToken || '',
  TESLA_USER_TOKEN_EXPIRES_AT: expiresAt,
  TESLA_OAUTH_STATE: '',
  TESLA_CODE_VERIFIER: ''
});

console.log('[oauth:exchange:sync] Token exchange OK. Saved user tokens to .env');
console.log(`[oauth:exchange:sync] access_token=${maskToken(accessToken)}`);
if (refreshToken) {
  console.log(`[oauth:exchange:sync] refresh_token=${maskToken(refreshToken)}`);
}
if (expiresAt) {
  console.log(`[oauth:exchange:sync] expires_at=${expiresAt}`);
}

if (!syncOnExchange) {
  console.log('[oauth:exchange:sync] TESLAMATE_SYNC_ON_EXCHANGE=0, skip TeslaMate runtime sync.');
  process.exit(0);
}

if (!refreshToken) {
  console.error('[oauth:exchange:sync] refresh_token is missing, cannot sync TeslaMate runtime session.');
  process.exit(3);
}

try {
  const sync = syncTokensToTeslaMateRuntime({
    accessToken,
    refreshToken,
    containerName
  });
  console.log(`[oauth:exchange:sync] TeslaMate runtime sync OK (container=${containerName})`);
  if (sync.stdout) {
    console.log('[oauth:exchange:sync] docker rpc output:');
    console.log(sync.stdout);
  }
} catch (error) {
  console.error('[oauth:exchange:sync] TeslaMate runtime sync failed.');
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(4);
}
