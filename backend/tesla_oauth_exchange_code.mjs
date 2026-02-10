import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { loadEnvFile, upsertEnvFile } from './env.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootEnv = path.resolve(__dirname, '../.env');

loadEnvFile(rootEnv);

const code = process.argv[2] || '';
const clientId = process.env.TESLA_CLIENT_ID || '';
const clientSecret = process.env.TESLA_CLIENT_SECRET || '';
const redirectUri = process.env.TESLA_REDIRECT_URI || '';
const codeVerifier = process.env.TESLA_CODE_VERIFIER || '';
const audience = process.env.TESLA_AUDIENCE || process.env.TESLA_FLEET_API_BASE || 'https://fleet-api.prd.na.vn.cloud.tesla.com';

if (!code) {
  console.error('[oauth:exchange] Missing code argument. Usage: node backend/tesla_oauth_exchange_code.mjs <code>');
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

const tokenUrl = 'https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token';

const body = new URLSearchParams();
body.set('grant_type', 'authorization_code');
body.set('client_id', clientId);
body.set('client_secret', clientSecret);
body.set('code', code);
body.set('code_verifier', codeVerifier);
body.set('audience', audience);
body.set('redirect_uri', redirectUri);

const res = await fetch(tokenUrl, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/x-www-form-urlencoded'
  },
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
  console.error('[oauth:exchange] Token exchange failed:', parsed?.error_description || parsed?.error || text);
  process.exit(2);
}

const accessToken = parsed?.access_token;
const refreshToken = parsed?.refresh_token;
const expiresIn = Number(parsed?.expires_in || 0);

if (!accessToken) {
  console.error('[oauth:exchange] Missing access_token in response.');
  process.exit(3);
}

const expiresAt = expiresIn ? new Date(Date.now() + expiresIn * 1000).toISOString() : '';

upsertEnvFile(rootEnv, {
  TESLA_USER_ACCESS_TOKEN: accessToken,
  TESLA_USER_REFRESH_TOKEN: refreshToken || '',
  TESLA_USER_TOKEN_EXPIRES_AT: expiresAt,
  TESLA_OAUTH_STATE: '',
  TESLA_CODE_VERIFIER: ''
});

console.log('[oauth:exchange] OK. Saved TESLA_USER_ACCESS_TOKEN (+ refresh token if provided) to .env');
console.log(`[oauth:exchange] access_token=${mask(accessToken)}`);
if (refreshToken) {
  console.log(`[oauth:exchange] refresh_token=${mask(refreshToken)}`);
}
if (expiresAt) {
  console.log(`[oauth:exchange] expires_at=${expiresAt}`);
}

function mask(token) {
  if (!token || token.length < 16) {
    return '(short)';
  }
  return token.slice(0, 8) + '...' + token.slice(-6);
}
