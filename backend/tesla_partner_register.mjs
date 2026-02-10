import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { loadEnvFile } from './env.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootEnv = path.resolve(__dirname, '../.env');

loadEnvFile(rootEnv);

const domain = process.env.TESLA_DOMAIN || '';
const clientId = process.env.TESLA_CLIENT_ID || '';
const clientSecret = process.env.TESLA_CLIENT_SECRET || '';
const audience = process.env.TESLA_AUDIENCE || process.env.TESLA_FLEET_API_BASE || 'https://fleet-api.prd.na.vn.cloud.tesla.com';
const fleetApiBase = process.env.TESLA_FLEET_API_BASE || 'https://fleet-api.prd.na.vn.cloud.tesla.com';

if (!domain) {
  console.error('[partner:register] Missing TESLA_DOMAIN in .env (example: tesla-subdash.example.com)');
  process.exit(1);
}

if (!clientId || !clientSecret) {
  console.error('[partner:register] Missing TESLA_CLIENT_ID / TESLA_CLIENT_SECRET in .env');
  process.exit(1);
}

const keyUrl = `https://${domain}/.well-known/appspecific/com.tesla.3p.public-key.pem`;

console.log('[partner:register] Checking public key URL:', keyUrl);
const keyRes = await fetch(keyUrl, { method: 'GET' });
if (!keyRes.ok) {
  console.error(`[partner:register] Public key not reachable (HTTP ${keyRes.status}).`);
  process.exit(2);
}

const partnerToken = await generatePartnerToken({ clientId, clientSecret, audience });

const registerUrl = `${fleetApiBase}/api/1/partner_accounts`;
const res = await fetch(registerUrl, {
  method: 'POST',
  headers: {
    Authorization: `Bearer ${partnerToken}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({ domain })
});

const text = await res.text();
let parsed;
try {
  parsed = text ? JSON.parse(text) : {};
} catch {
  parsed = { raw: text };
}

if (!res.ok) {
  console.error('[partner:register] Register failed:', parsed?.error || parsed?.message || text);
  process.exit(3);
}

console.log('[partner:register] OK:', JSON.stringify(parsed, null, 2));

async function generatePartnerToken({ clientId, clientSecret, audience }) {
  const tokenUrl = 'https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token';
  const body = new URLSearchParams();
  body.set('grant_type', 'client_credentials');
  body.set('client_id', clientId);
  body.set('client_secret', clientSecret);
  body.set('scope', 'openid');
  body.set('audience', audience);

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

  if (!res.ok || !parsed?.access_token) {
    throw new Error(parsed?.error_description || parsed?.error || text || 'Failed to get partner token');
  }

  return parsed.access_token;
}
