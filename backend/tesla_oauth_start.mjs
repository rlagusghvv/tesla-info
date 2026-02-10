import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { loadEnvFile, upsertEnvFile } from './env.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootEnv = path.resolve(__dirname, '../.env');

loadEnvFile(rootEnv);

const clientId = process.env.TESLA_CLIENT_ID || '';
const redirectUri = process.env.TESLA_REDIRECT_URI || '';
const audience = process.env.TESLA_AUDIENCE || process.env.TESLA_FLEET_API_BASE || 'https://fleet-api.prd.na.vn.cloud.tesla.com';

if (!clientId) {
  console.error('[oauth:start] TESLA_CLIENT_ID is missing in .env');
  process.exit(1);
}

if (!redirectUri) {
  console.error('[oauth:start] TESLA_REDIRECT_URI is missing in .env');
  process.exit(1);
}

const state = base64url(crypto.randomBytes(16));
const codeVerifier = base64url(crypto.randomBytes(48));
const codeChallenge = base64url(crypto.createHash('sha256').update(codeVerifier).digest());

upsertEnvFile(rootEnv, {
  TESLA_OAUTH_STATE: state,
  TESLA_CODE_VERIFIER: codeVerifier,
  TESLA_AUDIENCE: audience
});

const scopes = [
  'openid',
  'offline_access',
  'vehicle_device_data',
  'vehicle_cmds',
  'vehicle_charging_cmds'
].join(' ');

const authorize = new URL('https://auth.tesla.com/oauth2/v3/authorize');
authorize.searchParams.set('client_id', clientId);
authorize.searchParams.set('redirect_uri', redirectUri);
authorize.searchParams.set('response_type', 'code');
authorize.searchParams.set('scope', scopes);
authorize.searchParams.set('state', state);
authorize.searchParams.set('code_challenge', codeChallenge);
authorize.searchParams.set('code_challenge_method', 'S256');
authorize.searchParams.set('audience', audience);

console.log('[oauth:start] Open this URL in a browser, login, then copy the code from the callback page.');
console.log(authorize.toString());

function base64url(buf) {
  return buf
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}
