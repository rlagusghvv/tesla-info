const DEFAULT_TOKEN_URL = 'https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token';

export function parseOAuthCodeInput(input) {
  const raw = String(input || '').trim();
  if (!raw) {
    return '';
  }

  // Full callback URL case: https://.../oauth/callback?code=...
  if (/^https?:\/\//i.test(raw)) {
    try {
      const url = new URL(raw);
      const code = (url.searchParams.get('code') || '').trim();
      if (code) {
        return code;
      }
    } catch {
      // Fall through to query-string parsing.
    }
  }

  // Raw query-string case: code=...&state=...
  if (raw.startsWith('?') || raw.includes('code=')) {
    const query = raw.startsWith('?') ? raw.slice(1) : raw.includes('?') ? raw.split('?').slice(1).join('?') : raw;
    const params = new URLSearchParams(query);
    const code = (params.get('code') || '').trim();
    if (code) {
      return code;
    }
  }

  // Plain code value case.
  return raw;
}

export async function exchangeAuthorizationCode({
  codeInput,
  clientId,
  clientSecret,
  redirectUri,
  codeVerifier,
  audience,
  tokenUrl = DEFAULT_TOKEN_URL,
  fetchImpl = fetch
}) {
  const code = parseOAuthCodeInput(codeInput);
  if (!code) {
    throw new Error('Missing code. Pass Tesla callback URL or raw authorization code.');
  }

  const body = new URLSearchParams();
  body.set('grant_type', 'authorization_code');
  body.set('client_id', String(clientId || ''));
  body.set('client_secret', String(clientSecret || ''));
  body.set('code', code);
  body.set('code_verifier', String(codeVerifier || ''));
  body.set('redirect_uri', String(redirectUri || ''));
  body.set('audience', String(audience || ''));

  const res = await fetchImpl(tokenUrl, {
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
    const message = parsed?.error_description || parsed?.error || text || `HTTP ${res.status}`;
    const error = new Error(`Token exchange failed (${res.status}): ${message}`);
    error.status = res.status;
    error.response = parsed;
    throw error;
  }

  const accessToken = parsed?.access_token || '';
  const refreshToken = parsed?.refresh_token || '';
  const expiresIn = Number(parsed?.expires_in || 0);
  const expiresAt = expiresIn ? new Date(Date.now() + expiresIn * 1000).toISOString() : '';

  if (!accessToken) {
    throw new Error('Token exchange succeeded but access_token is missing.');
  }

  return {
    code,
    accessToken,
    refreshToken,
    expiresAt,
    raw: parsed
  };
}

export function maskToken(token) {
  const value = String(token || '');
  if (!value || value.length < 16) {
    return '(short)';
  }
  return `${value.slice(0, 8)}...${value.slice(-6)}`;
}
