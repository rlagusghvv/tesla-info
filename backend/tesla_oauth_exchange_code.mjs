import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { loadEnvFile, upsertEnvFile } from './env.mjs';
import { exchangeAuthorizationCode, maskToken } from './tesla_oauth_common.mjs';

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

if (!codeInput) {
  console.error(
    '[oauth:exchange] Missing argument. Usage: node backend/tesla_oauth_exchange_code.mjs <code-or-callback-url>'
  );
  process.exit(1);
}

if (!clientId || !clientSecret || !redirectUri) {
  console.error('[oauth:exchange] Missing TESLA_CLIENT_ID / TESLA_CLIENT_SECRET / TESLA_REDIRECT_URI in .env');
  process.exit(1);
}

if (!codeVerifier) {
  console.error('[oauth:exchange] Missing TESLA_CODE_VERIFIER in .env. Run npm run tesla:oauth:start first.');
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
  console.error('[oauth:exchange]', error instanceof Error ? error.message : 'Token exchange failed.');
  process.exit(3);
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

console.log('[oauth:exchange] OK. Saved TESLA_USER_ACCESS_TOKEN (+ refresh token if provided) to .env');
console.log(`[oauth:exchange] access_token=${maskToken(accessToken)}`);
if (refreshToken) {
  console.log(`[oauth:exchange] refresh_token=${maskToken(refreshToken)}`);
}
if (expiresAt) {
  console.log(`[oauth:exchange] expires_at=${expiresAt}`);
}
