import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { loadEnvFile, upsertEnvFile } from './env.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootEnv = path.resolve(__dirname, '../.env');

loadEnvFile(rootEnv);

const clientId = process.env.TESLA_CLIENT_ID || '';
const refreshToken = process.env.TESLA_USER_REFRESH_TOKEN || '';
const clientSecret = process.env.TESLA_CLIENT_SECRET || '';

if (!clientId || !refreshToken) {
  console.error('[oauth:refresh] Missing TESLA_CLIENT_ID or TESLA_USER_REFRESH_TOKEN in .env');
  process.exit(1);
}

const tokenUrl = 'https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token';

const body = new URLSearchParams();
body.set('grant_type', 'refresh_token');
body.set('client_id', clientId);
body.set('refresh_token', refreshToken);

// Tesla docs show client_secret is not required for refresh_token, but keep compatibility.
if (clientSecret) {
  body.set('client_secret', clientSecret);
}

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
  console.error('[oauth:refresh] Refresh failed:', parsed?.error_description || parsed?.error || text);
  process.exit(2);
}

const accessToken = parsed?.access_token;
const newRefreshToken = parsed?.refresh_token;
const expiresIn = Number(parsed?.expires_in || 0);

if (!accessToken) {
  console.error('[oauth:refresh] Missing access_token in response.');
  process.exit(3);
}

const expiresAt = expiresIn ? new Date(Date.now() + expiresIn * 1000).toISOString() : '';

upsertEnvFile(rootEnv, {
  TESLA_USER_ACCESS_TOKEN: accessToken,
  TESLA_USER_TOKEN_EXPIRES_AT: expiresAt,
  TESLA_USER_REFRESH_TOKEN: newRefreshToken || refreshToken
});

console.log('[oauth:refresh] OK. Saved refreshed token to .env');
console.log(`[oauth:refresh] access_token=${mask(accessToken)}`);
if (newRefreshToken) {
  console.log(`[oauth:refresh] refresh_token=${mask(newRefreshToken)}`);
}
if (expiresAt) {
  console.log(`[oauth:refresh] expires_at=${expiresAt}`);
}

function mask(token) {
  if (!token || token.length < 16) {
    return '(short)';
  }
  return token.slice(0, 8) + '...' + token.slice(-6);
}
