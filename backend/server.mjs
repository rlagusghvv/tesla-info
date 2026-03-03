import fs from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { loadEnvFile, upsertEnvFile } from './env.mjs';
import { exchangeAuthorizationCode } from './tesla_oauth_common.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT_ENV_PATH = path.resolve(__dirname, '../.env');

loadEnvFile(ROOT_ENV_PATH);

const SPEED_CAMERA_DATA_PATH = path.resolve(
  __dirname,
  process.env.SPEED_CAMERA_DATA_PATH || './data/speed_cameras_kr.min.json'
);
const PRIVACY_HTML_PATH = path.resolve(__dirname, './public/privacy.html');
const SUPPORT_HTML_PATH = path.resolve(__dirname, './public/support.html');
const TERMS_HTML_PATH = path.resolve(__dirname, './public/terms.html');

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || '127.0.0.1';
const USE_SIMULATOR = process.env.USE_SIMULATOR !== '0';
const MODE = USE_SIMULATOR ? 'simulator' : 'fleet';
const POLL_ENABLED = process.env.POLL_TESLA === '1' || process.env.POLL_ENABLED === '1';
const POLL_INTERVAL_MS = Number(process.env.POLL_INTERVAL_MS || 8000);
let TESLA_USER_ACCESS_TOKEN = process.env.TESLA_USER_ACCESS_TOKEN || process.env.TESLA_ACCESS_TOKEN || '';
let TESLA_USER_REFRESH_TOKEN = process.env.TESLA_USER_REFRESH_TOKEN || '';
const TESLA_VIN = process.env.TESLA_VIN || '';
const TESLA_FLEET_API_BASE = process.env.TESLA_FLEET_API_BASE || 'https://fleet-api.prd.na.vn.cloud.tesla.com';
let TESLA_TOKEN_GRANT_TYPE = inferJwtGrantType(TESLA_USER_ACCESS_TOKEN);
const TESLA_CLIENT_ID = process.env.TESLA_CLIENT_ID || '';
const TESLA_CLIENT_SECRET = process.env.TESLA_CLIENT_SECRET || '';
const TESLA_TOKEN_URL = process.env.TESLA_TOKEN_URL || 'https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token';
const BACKEND_API_TOKEN = process.env.BACKEND_API_TOKEN || '';
const APP_USERS_PATH = path.resolve(__dirname, process.env.APP_USERS_PATH || './data/app_users.json');
const APP_DEFAULT_ADMIN_USERNAME = 'admin';
const APP_DEFAULT_ADMIN_PASSWORD = 'admin';
const KAKAO_REST_API_KEY = process.env.KAKAO_REST_API_KEY || '';
const KAKAO_JAVASCRIPT_KEY = process.env.KAKAO_JAVASCRIPT_KEY || '';
const APP_AUTH_SESSION_TTL_MS = Math.max(60_000, Number(process.env.APP_AUTH_SESSION_TTL_MS || 86_400_000));
const ENFORCE_BACKEND_API_TOKEN = (() => {
  const raw = String(process.env.ENFORCE_BACKEND_API_TOKEN || '').trim();
  if (raw) {
    return raw !== '0';
  }
  // Secure-by-default for non-simulator modes.
  return MODE !== 'simulator';
})();
const runtime = {
  resolvedVin: TESLA_VIN,
  resolvedDisplayName: ''
};

if (ENFORCE_BACKEND_API_TOKEN && !BACKEND_API_TOKEN) {
  console.error('[tesla-subdash-backend] BACKEND_API_TOKEN is required when backend auth is enforced.');
  console.error('[tesla-subdash-backend] Set BACKEND_API_TOKEN in .env (or set ENFORCE_BACKEND_API_TOKEN=0 for local-only debug).');
  process.exit(1);
}

const appSessions = new Map();
const appUsersByUsername = new Map();

const SIM_ROUTE = [
  { lat: 37.498095, lon: 127.02761 },
  { lat: 37.49889, lon: 127.03035 },
  { lat: 37.500115, lon: 127.033035 },
  { lat: 37.50145, lon: 127.0358 },
  { lat: 37.50323, lon: 127.03912 },
  { lat: 37.504005, lon: 127.04174 },
  { lat: 37.50322, lon: 127.04464 },
  { lat: 37.50174, lon: 127.04695 },
  { lat: 37.49963, lon: 127.04861 },
  { lat: 37.49758, lon: 127.04903 },
  { lat: 37.49543, lon: 127.04837 },
  { lat: 37.49392, lon: 127.04619 },
  { lat: 37.49301, lon: 127.04334 },
  { lat: 37.49352, lon: 127.04016 },
  { lat: 37.49488, lon: 127.03732 },
  { lat: 37.49645, lon: 127.03457 },
  { lat: 37.49751, lon: 127.03165 },
  { lat: 37.498095, lon: 127.02761 }
];

let simIndex = 0;

const state = {
  mode: MODE,
  source: MODE === 'simulator' ? 'simulator' : 'startup',
  lastCommand: null,
  updatedAt: new Date().toISOString(),
  navigation: null,
  vehicle: {
    vin: MODE === 'fleet' ? TESLA_VIN || 'FLEET_VIN' : 'SIMULATED_VIN',
    displayName: 'Model Y',
    onlineState: 'online',
    batteryLevel: 78,
    usableBatteryLevel: 76,
    estimatedRangeKm: 402,
    insideTempC: 23.0,
    outsideTempC: 10.0,
    odometerKm: 21483.4,
    speedKph: 0,
    headingDeg: 0,
    isLocked: true,
    isClimateOn: false,
    location: {
      lat: SIM_ROUTE[0].lat,
      lon: SIM_ROUTE[0].lon
    }
  }
};
let fleetUserTokenRefreshInFlight = null;

function sendJson(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Backend-Token,X-App-Session,X-Api-Key'
  });
  res.end(payload);
}

async function sendHtmlFile(res, filePath) {
  const html = await fs.readFile(filePath, 'utf8');
  res.writeHead(200, {
    'Content-Type': 'text/html; charset=utf-8',
    'Content-Length': Buffer.byteLength(html)
  });
  res.end(html);
}

const STATIC_PAGE_PATHS = new Map([
  ['/privacy', PRIVACY_HTML_PATH],
  ['/privacy/', PRIVACY_HTML_PATH],
  ['/support', SUPPORT_HTML_PATH],
  ['/support/', SUPPORT_HTML_PATH],
  ['/terms', TERMS_HTML_PATH],
  ['/terms/', TERMS_HTML_PATH]
]);

function requireBackendToken(req) {
  if (!ENFORCE_BACKEND_API_TOKEN) {
    return { ok: true };
  }
  if (!BACKEND_API_TOKEN) {
    return { ok: false, message: 'Server misconfigured (BACKEND_API_TOKEN missing).' };
  }

  const header = String(req.headers['x-backend-token'] || '').trim();
  const auth = String(req.headers.authorization || '').trim();
  const bearer = auth.toLowerCase().startsWith('bearer ') ? auth.slice(7).trim() : '';

  if (header === BACKEND_API_TOKEN || bearer === BACKEND_API_TOKEN) {
    return { ok: true };
  }
  return { ok: false, message: 'Unauthorized (missing/invalid backend token).' };
}

function requireBackendTokenOrRespond(req, res) {
  const authz = requireBackendToken(req);
  if (authz.ok) return true;
  sendJson(res, 401, { ok: false, message: authz.message });
  return false;
}

function hashSecret(secret, salt) {
  return crypto.scryptSync(String(secret || ''), String(salt || ''), 64).toString('hex');
}

function timingSafeEqualString(left, right) {
  const a = Buffer.from(String(left || ''), 'utf8');
  const b = Buffer.from(String(right || ''), 'utf8');
  if (a.length !== b.length) {
    return false;
  }
  return crypto.timingSafeEqual(a, b);
}

function resolveRequestOrigin(req) {
  const forwardedProto = String(req.headers['x-forwarded-proto'] || '')
    .split(',')[0]
    .trim();
  const forwardedHost = String(req.headers['x-forwarded-host'] || '')
    .split(',')[0]
    .trim();
  const host = forwardedHost || String(req.headers.host || '').trim();
  if (!host) {
    return null;
  }
  const proto = forwardedProto || 'http';
  return `${proto}://${host}`;
}

function normalizeUsername(raw) {
  return String(raw || '').trim().toLowerCase();
}

function isValidUsername(username) {
  return /^[a-z0-9._-]{3,32}$/.test(String(username || ''));
}

function isValidPassword(password) {
  const value = String(password || '');
  return value.length >= 4 && value.length <= 128;
}

function sanitizeTrimmedString(raw, { maxLength = 2048 } = {}) {
  const text = String(raw ?? '').trim();
  if (!text) return '';
  return text.length > maxLength ? text.slice(0, maxLength) : text;
}

function hashUserPassword(username, password) {
  const normalizedUsername = normalizeUsername(username);
  return hashSecret(password, `subdash-user-password-v1:${normalizedUsername}`);
}

function defaultTeslaSettingsForUser() {
  return {
    clientId: '',
    clientSecret: '',
    redirectURI: process.env.TESLA_REDIRECT_URI || '',
    audience: process.env.TESLA_AUDIENCE || TESLA_FLEET_API_BASE || '',
    fleetApiBase: TESLA_FLEET_API_BASE || ''
  };
}

function defaultTeslaSettingsForAdminSeed() {
  return {
    clientId: TESLA_CLIENT_ID || '',
    clientSecret: TESLA_CLIENT_SECRET || '',
    redirectURI: process.env.TESLA_REDIRECT_URI || '',
    audience: process.env.TESLA_AUDIENCE || TESLA_FLEET_API_BASE || '',
    fleetApiBase: TESLA_FLEET_API_BASE || ''
  };
}

function normalizeTeslaSettings(raw, fallback = defaultTeslaSettingsForUser()) {
  const source = raw && typeof raw === 'object' ? raw : {};
  return {
    clientId: sanitizeTrimmedString(source.clientId ?? fallback.clientId ?? '', { maxLength: 1024 }),
    clientSecret: sanitizeTrimmedString(source.clientSecret ?? fallback.clientSecret ?? '', { maxLength: 1024 }),
    redirectURI: sanitizeTrimmedString(source.redirectURI ?? fallback.redirectURI ?? '', { maxLength: 1024 }),
    audience: sanitizeTrimmedString(source.audience ?? fallback.audience ?? '', { maxLength: 1024 }),
    fleetApiBase: sanitizeTrimmedString(source.fleetApiBase ?? fallback.fleetApiBase ?? '', { maxLength: 1024 })
  };
}

function normalizeKakaoSettings(raw, fallback = { restAPIKey: '', javaScriptKey: '' }) {
  const source = raw && typeof raw === 'object' ? raw : {};
  return {
    restAPIKey: sanitizeTrimmedString(source.restAPIKey ?? fallback.restAPIKey ?? '', { maxLength: 1024 }),
    javaScriptKey: sanitizeTrimmedString(source.javaScriptKey ?? fallback.javaScriptKey ?? '', { maxLength: 1024 })
  };
}

function createUserRecord({ username, password, role = 'member', settings = null }) {
  const normalizedUsername = normalizeUsername(username);
  const now = new Date().toISOString();
  return {
    username: normalizedUsername,
    role: role === 'admin' ? 'admin' : 'member',
    passwordHash: hashUserPassword(normalizedUsername, password),
    createdAt: now,
    updatedAt: now,
    settings: {
      tesla: normalizeTeslaSettings(settings?.tesla ?? null, defaultTeslaSettingsForUser()),
      kakao: normalizeKakaoSettings(settings?.kakao ?? null, { restAPIKey: '', javaScriptKey: '' })
    }
  };
}

function normalizeLoadedUserRecord(raw) {
  const username = normalizeUsername(raw?.username);
  if (!username) return null;
  const passwordHash = sanitizeTrimmedString(raw?.passwordHash ?? '', { maxLength: 1024 });
  if (!passwordHash) return null;
  return {
    username,
    role: String(raw?.role || '').toLowerCase() === 'admin' ? 'admin' : 'member',
    passwordHash,
    createdAt: sanitizeTrimmedString(raw?.createdAt ?? '', { maxLength: 128 }) || new Date().toISOString(),
    updatedAt: sanitizeTrimmedString(raw?.updatedAt ?? '', { maxLength: 128 }) || new Date().toISOString(),
    settings: {
      tesla: normalizeTeslaSettings(raw?.settings?.tesla ?? null, defaultTeslaSettingsForUser()),
      kakao: normalizeKakaoSettings(raw?.settings?.kakao ?? null, { restAPIKey: '', javaScriptKey: '' })
    }
  };
}

function listStoredUsers() {
  return Array.from(appUsersByUsername.values()).sort((a, b) => a.username.localeCompare(b.username));
}

let appUsersWriteChain = Promise.resolve();

function queuePersistUsers() {
  appUsersWriteChain = appUsersWriteChain.catch(() => {}).then(async () => {
    await fs.mkdir(path.dirname(APP_USERS_PATH), { recursive: true });
    const payload = {
      version: 1,
      users: listStoredUsers()
    };
    await fs.writeFile(APP_USERS_PATH, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
  });
  return appUsersWriteChain;
}

function fillIfMissing(target, key, value) {
  const next = sanitizeTrimmedString(value ?? '', { maxLength: 1024 });
  if (!next) return false;
  if (sanitizeTrimmedString(target?.[key] ?? '', { maxLength: 1024 })) return false;
  target[key] = next;
  return true;
}

function ensureAdminSeedUser() {
  const adminUsername = APP_DEFAULT_ADMIN_USERNAME;
  const adminPasswordHash = hashUserPassword(adminUsername, APP_DEFAULT_ADMIN_PASSWORD);
  const adminTeslaSeed = normalizeTeslaSettings(defaultTeslaSettingsForAdminSeed(), defaultTeslaSettingsForAdminSeed());
  const adminKakaoSeed = normalizeKakaoSettings(
    {
      restAPIKey: KAKAO_REST_API_KEY,
      javaScriptKey: KAKAO_JAVASCRIPT_KEY
    },
    { restAPIKey: '', javaScriptKey: '' }
  );

  const existing = appUsersByUsername.get(adminUsername);
  if (!existing) {
    appUsersByUsername.set(
      adminUsername,
      createUserRecord({
        username: adminUsername,
        password: APP_DEFAULT_ADMIN_PASSWORD,
        role: 'admin',
        settings: {
          tesla: adminTeslaSeed,
          kakao: adminKakaoSeed
        }
      })
    );
    return true;
  }

  let changed = false;
  if (existing.role !== 'admin') {
    existing.role = 'admin';
    changed = true;
  }

  // Keep admin/admin deterministic as requested.
  if (!timingSafeEqualString(existing.passwordHash, adminPasswordHash)) {
    existing.passwordHash = adminPasswordHash;
    changed = true;
  }

  existing.settings = {
    tesla: normalizeTeslaSettings(existing.settings?.tesla ?? null, defaultTeslaSettingsForUser()),
    kakao: normalizeKakaoSettings(existing.settings?.kakao ?? null, { restAPIKey: '', javaScriptKey: '' })
  };

  changed = fillIfMissing(existing.settings.tesla, 'clientId', adminTeslaSeed.clientId) || changed;
  changed = fillIfMissing(existing.settings.tesla, 'clientSecret', adminTeslaSeed.clientSecret) || changed;
  changed = fillIfMissing(existing.settings.tesla, 'redirectURI', adminTeslaSeed.redirectURI) || changed;
  changed = fillIfMissing(existing.settings.tesla, 'audience', adminTeslaSeed.audience) || changed;
  changed = fillIfMissing(existing.settings.tesla, 'fleetApiBase', adminTeslaSeed.fleetApiBase) || changed;
  changed = fillIfMissing(existing.settings.kakao, 'restAPIKey', adminKakaoSeed.restAPIKey) || changed;
  changed = fillIfMissing(existing.settings.kakao, 'javaScriptKey', adminKakaoSeed.javaScriptKey) || changed;

  if (changed) {
    existing.updatedAt = new Date().toISOString();
  }
  return changed;
}

async function initializeAppUsers() {
  appUsersByUsername.clear();
  let changed = false;
  try {
    const raw = await fs.readFile(APP_USERS_PATH, 'utf8');
    const parsed = JSON.parse(raw);
    const users = Array.isArray(parsed?.users) ? parsed.users : [];
    for (const candidate of users) {
      const normalized = normalizeLoadedUserRecord(candidate);
      if (!normalized) continue;
      appUsersByUsername.set(normalized.username, normalized);
    }
  } catch (error) {
    if (error?.code !== 'ENOENT') {
      throw error;
    }
    changed = true;
  }

  changed = ensureAdminSeedUser() || changed;
  if (changed) {
    await queuePersistUsers();
  }
}

function getUserByUsername(username) {
  const normalized = normalizeUsername(username);
  if (!normalized) return null;
  return appUsersByUsername.get(normalized) || null;
}

function toPublicUser(user) {
  return {
    username: user.username,
    role: user.role
  };
}

function resolveAdminSeedSettings() {
  const adminUser = appUsersByUsername.get(APP_DEFAULT_ADMIN_USERNAME) || null;
  const adminTesla = normalizeTeslaSettings(adminUser?.settings?.tesla ?? null, defaultTeslaSettingsForAdminSeed());
  const adminKakao = normalizeKakaoSettings(
    adminUser?.settings?.kakao ?? null,
    {
      restAPIKey: KAKAO_REST_API_KEY,
      javaScriptKey: KAKAO_JAVASCRIPT_KEY
    }
  );
  return { adminTesla, adminKakao };
}

function buildUserBootstrap(req, user) {
  const settings = user?.settings || {};
  const isAdmin = String(user?.role || '').toLowerCase() === 'admin';
  const { adminTesla, adminKakao } = resolveAdminSeedSettings();
  const teslaSource = isAdmin ? settings.tesla ?? null : adminTesla;
  const kakaoSource = settings.kakao ?? null;
  return {
    backendBaseURL: resolveRequestOrigin(req),
    backendApiToken: BACKEND_API_TOKEN || '',
    telemetrySource: 'backend',
    tesla: normalizeTeslaSettings(teslaSource, adminTesla),
    kakao: normalizeKakaoSettings(kakaoSource, isAdmin ? adminKakao : { restAPIKey: '', javaScriptKey: '' })
  };
}

function issueAppSession({ username, role = 'member' }) {
  const token = crypto.randomBytes(32).toString('base64url');
  const nowMs = Date.now();
  const session = {
    token,
    username: normalizeUsername(username),
    role,
    createdAt: new Date(nowMs).toISOString(),
    lastSeenAt: new Date(nowMs).toISOString(),
    expiresAt: new Date(nowMs + APP_AUTH_SESSION_TTL_MS).toISOString()
  };
  appSessions.set(token, session);
  return session;
}

function pruneExpiredAppSessions() {
  const nowMs = Date.now();
  for (const [token, session] of appSessions.entries()) {
    const expiresAtMs = Date.parse(session?.expiresAt || '');
    if (!Number.isFinite(expiresAtMs) || expiresAtMs <= nowMs) {
      appSessions.delete(token);
    }
  }
}

function getAppSessionToken(req) {
  const auth = String(req.headers.authorization || '').trim();
  const bearer = auth.toLowerCase().startsWith('bearer ') ? auth.slice(7).trim() : '';
  const headerToken = String(req.headers['x-app-session'] || '').trim();
  return bearer || headerToken;
}

function requireAppSession(req) {
  pruneExpiredAppSessions();
  const token = getAppSessionToken(req);
  if (!token) {
    return { ok: false, message: 'Unauthorized (missing app session token).' };
  }
  const session = appSessions.get(token);
  if (!session) {
    return { ok: false, message: 'Unauthorized (invalid or expired app session).' };
  }
  const user = getUserByUsername(session.username);
  if (!user) {
    appSessions.delete(token);
    return { ok: false, message: 'Unauthorized (account not found).' };
  }
  session.lastSeenAt = new Date().toISOString();
  return { ok: true, token, session, user };
}

function requireAppSessionOrRespond(req, res) {
  const authz = requireAppSession(req);
  if (authz.ok) {
    return authz;
  }
  sendJson(res, 401, { ok: false, message: authz.message });
  return null;
}

function inferJwtGrantType(token) {
  try {
    const parts = String(token || '').split('.');
    if (parts.length < 2) {
      return null;
    }
    const payload = Buffer.from(base64urlToBase64(parts[1]), 'base64').toString('utf8');
    const parsed = JSON.parse(payload);
    return typeof parsed?.gty === 'string' ? parsed.gty : null;
  } catch {
    return null;
  }
}

function base64urlToBase64(s) {
  const normalized = String(s || '').replace(/-/g, '+').replace(/_/g, '/');
  const padLen = (4 - (normalized.length % 4)) % 4;
  return normalized + '='.repeat(padLen);
}

function toKph(mph) {
  if (typeof mph !== 'number') {
    return null;
  }
  return mph * 1.60934;
}

function milesToKm(mi) {
  if (typeof mi !== 'number') {
    return null;
  }
  return mi * 1.60934;
}

function listLanIPv4() {
  const nets = os.networkInterfaces();
  const results = [];
  for (const [name, addrs] of Object.entries(nets)) {
    for (const addr of addrs || []) {
      if (!addr || addr.family !== 'IPv4' || addr.internal) {
        continue;
      }
      const ip = addr.address;
      if (!ip || ip.startsWith('169.254.')) {
        continue;
      }
      results.push({ name, ip });
    }
  }

  const seen = new Set();
  return results.filter((entry) => {
    if (seen.has(entry.ip)) {
      return false;
    }
    seen.add(entry.ip);
    return true;
  });
}

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  if (!chunks.length) {
    return {};
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function applyPatch(patch, source = 'patch') {
  const nextNavigation =
    patch && Object.prototype.hasOwnProperty.call(patch, 'navigation')
      ? normalizeNavigationState(patch.navigation)
      : state.navigation;
  const vehiclePatch = patch && typeof patch === 'object' ? { ...patch } : {};
  delete vehiclePatch.navigation;

  const nextVehicle = {
    ...state.vehicle,
    ...vehiclePatch,
    location: {
      ...state.vehicle.location,
      ...(vehiclePatch.location || {})
    }
  };

  state.vehicle = nextVehicle;
  state.navigation = nextNavigation;
  state.source = source;
  state.updatedAt = new Date().toISOString();
}

function snapshotResponse() {
  return {
    source: state.source,
    mode: state.mode,
    updatedAt: state.updatedAt,
    lastCommand: state.lastCommand,
    navigation: state.navigation,
    vehicle: state.vehicle
  };
}

function tickSimulator() {
  simIndex = (simIndex + 1) % SIM_ROUTE.length;
  const current = SIM_ROUTE[simIndex];
  const next = SIM_ROUTE[(simIndex + 1) % SIM_ROUTE.length];
  const heading = Math.atan2(next.lon - current.lon, next.lat - current.lat) * 180 / Math.PI;

  const nextBattery = Math.max(20, state.vehicle.batteryLevel - 0.01);
  const speed = 42 + Math.round(Math.random() * 23);

  applyPatch(
    {
      location: { lat: current.lat, lon: current.lon },
      speedKph: speed,
      headingDeg: (heading + 360) % 360,
      batteryLevel: Number(nextBattery.toFixed(2)),
      usableBatteryLevel: Number((nextBattery - 2).toFixed(2)),
      estimatedRangeKm: Number((nextBattery * 5.1).toFixed(1)),
      insideTempC: Number((22 + Math.random() * 2).toFixed(1)),
      outsideTempC: Number((9 + Math.random() * 4).toFixed(1)),
      onlineState: 'online'
    },
    'simulator'
  );
}

function applySimCommand(command) {
  switch (command) {
    case 'door_lock':
    case 'lock':
      applyPatch({ isLocked: true }, 'sim_command');
      return { ok: true, message: 'Vehicle locked (simulated).' };
    case 'door_unlock':
    case 'unlock':
      applyPatch({ isLocked: false }, 'sim_command');
      return { ok: true, message: 'Vehicle unlocked (simulated).' };
    case 'auto_conditioning_start':
    case 'climate_on':
      applyPatch({ isClimateOn: true }, 'sim_command');
      return { ok: true, message: 'Climate ON (simulated).' };
    case 'auto_conditioning_stop':
    case 'climate_off':
      applyPatch({ isClimateOn: false }, 'sim_command');
      return { ok: true, message: 'Climate OFF (simulated).' };
    case 'wake_up':
      applyPatch({ onlineState: 'online' }, 'sim_command');
      return { ok: true, message: 'Vehicle wake-up simulated.' };
    case 'navigation_waypoints_request':
    case 'navigation_request':
      return { ok: true, message: 'Navigation destination sent (simulated).' };
    default:
      return { ok: false, message: `Unsupported simulated command: ${command}` };
  }
}

function toFiniteNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function normalizeNavigationDestination(payload) {
  if (!payload || typeof payload !== 'object') {
    return null;
  }

  const source = payload;
  let lat = toFiniteNumber(source.lat ?? source.latitude);
  let lon = toFiniteNumber(source.lon ?? source.lng ?? source.longitude);
  let name = String(source.name || source.label || source.title || '').trim();

  if ((!Number.isFinite(lat) || !Number.isFinite(lon)) && Array.isArray(source.waypoints) && source.waypoints.length) {
    const first = source.waypoints[0] || {};
    lat = toFiniteNumber(first.lat ?? first.latitude);
    lon = toFiniteNumber(first.lon ?? first.lng ?? first.longitude);
    if (!name) {
      name = String(first.name || first.label || '').trim();
    }
  }

  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    return null;
  }

  return {
    lat,
    lon,
    name: name || 'Destination'
  };
}

function normalizeNavigationState(raw) {
  if (raw === null) {
    return null;
  }
  if (!raw || typeof raw !== 'object') {
    return null;
  }

  const destinationName = String(raw.destinationName || raw.name || '').trim() || null;
  const lat = toFiniteNumber(raw.destination?.lat ?? raw.destinationLat ?? raw.lat);
  const lon = toFiniteNumber(raw.destination?.lon ?? raw.destinationLon ?? raw.lon ?? raw.lng);
  const remainingKm = toFiniteNumber(raw.remainingKm);
  const etaMinutesRaw = toFiniteNumber(raw.etaMinutes);
  const trafficDelayMinutesRaw = toFiniteNumber(raw.trafficDelayMinutes);
  const energyAtArrivalPercent = toFiniteNumber(raw.energyAtArrivalPercent);

  const hasValidCoordinates =
    Number.isFinite(lat) &&
    Number.isFinite(lon) &&
    lat >= -90 &&
    lat <= 90 &&
    lon >= -180 &&
    lon <= 180 &&
    (Math.abs(lat) > 0.00001 || Math.abs(lon) > 0.00001);

  const normalized = {
    destinationName,
    destination: hasValidCoordinates ? { lat, lon } : null,
    remainingKm: Number.isFinite(remainingKm) ? Math.max(0, remainingKm) : null,
    etaMinutes: Number.isFinite(etaMinutesRaw) ? Math.max(0, Math.round(etaMinutesRaw)) : null,
    trafficDelayMinutes: Number.isFinite(trafficDelayMinutesRaw) ? Math.max(0, Math.round(trafficDelayMinutesRaw)) : null,
    energyAtArrivalPercent: Number.isFinite(energyAtArrivalPercent) ? energyAtArrivalPercent : null
  };

  if (
    !normalized.destinationName &&
    !normalized.destination &&
    normalized.remainingKm == null &&
    normalized.etaMinutes == null &&
    normalized.trafficDelayMinutes == null &&
    normalized.energyAtArrivalPercent == null
  ) {
    return null;
  }

  return normalized;
}

function mapNavigationFromDriveState(drive) {
  if (!drive || typeof drive !== 'object') {
    return null;
  }

  return normalizeNavigationState({
    destinationName: drive.active_route_destination || null,
    destination: {
      lat: drive.active_route_latitude,
      lon: drive.active_route_longitude
    },
    remainingKm: milesToKm(toFiniteNumber(drive.active_route_miles_to_arrival)),
    etaMinutes: toFiniteNumber(drive.active_route_minutes_to_arrival),
    trafficDelayMinutes: toFiniteNumber(drive.active_route_traffic_minutes_delay),
    energyAtArrivalPercent: toFiniteNumber(drive.active_route_energy_at_arrival)
  });
}

function summarizeFleetCommand(parsed, status, fallbackFailure = 'Command failed') {
  const result = parsed?.response?.result;
  const success = typeof result === 'boolean' ? result : true;
  return {
    ok: success,
    status,
    message: parsed?.response?.reason || parsed?.error || parsed?.message || (success ? 'OK' : fallbackFailure),
    body: parsed
  };
}

function normalizeIngestPayload(payload) {
  const vehicle = payload.vehicle || {};
  const navigation = normalizeNavigationState(payload.navigation ?? vehicle.navigation ?? null);

  return {
    vin: vehicle.vin || payload.vin || state.vehicle.vin,
    displayName: vehicle.displayName || state.vehicle.displayName,
    onlineState: vehicle.onlineState || payload.onlineState || state.vehicle.onlineState,
    batteryLevel: typeof vehicle.batteryLevel === 'number' ? vehicle.batteryLevel : state.vehicle.batteryLevel,
    usableBatteryLevel:
      typeof vehicle.usableBatteryLevel === 'number' ? vehicle.usableBatteryLevel : state.vehicle.usableBatteryLevel,
    estimatedRangeKm:
      typeof vehicle.estimatedRangeKm === 'number' ? vehicle.estimatedRangeKm : state.vehicle.estimatedRangeKm,
    insideTempC: typeof vehicle.insideTempC === 'number' ? vehicle.insideTempC : state.vehicle.insideTempC,
    outsideTempC: typeof vehicle.outsideTempC === 'number' ? vehicle.outsideTempC : state.vehicle.outsideTempC,
    odometerKm: typeof vehicle.odometerKm === 'number' ? vehicle.odometerKm : state.vehicle.odometerKm,
    speedKph: typeof vehicle.speedKph === 'number' ? vehicle.speedKph : state.vehicle.speedKph,
    headingDeg: typeof vehicle.headingDeg === 'number' ? vehicle.headingDeg : state.vehicle.headingDeg,
    isLocked: typeof vehicle.isLocked === 'boolean' ? vehicle.isLocked : state.vehicle.isLocked,
    isClimateOn: typeof vehicle.isClimateOn === 'boolean' ? vehicle.isClimateOn : state.vehicle.isClimateOn,
    location: {
      lat: vehicle.location?.lat ?? payload.lat ?? state.vehicle.location.lat,
      lon: vehicle.location?.lon ?? payload.lon ?? state.vehicle.location.lon
    },
    navigation
  };
}

function mapTeslaVehicleDataToSnapshot(vehicleData) {
  const drive = vehicleData.drive_state || {};
  const charge = vehicleData.charge_state || {};
  const climate = vehicleData.climate_state || {};
  const vehicleState = vehicleData.vehicle_state || {};
  const navigation = mapNavigationFromDriveState(drive);

  return {
    vin: vehicleData.vin || state.vehicle.vin,
    displayName: vehicleData.display_name || state.vehicle.displayName,
    onlineState: vehicleData.state || state.vehicle.onlineState,
    batteryLevel: charge.battery_level ?? state.vehicle.batteryLevel,
    usableBatteryLevel: charge.usable_battery_level ?? state.vehicle.usableBatteryLevel,
    estimatedRangeKm: milesToKm(charge.battery_range) ?? state.vehicle.estimatedRangeKm,
    insideTempC: climate.inside_temp ?? state.vehicle.insideTempC,
    outsideTempC: climate.outside_temp ?? state.vehicle.outsideTempC,
    odometerKm: milesToKm(vehicleState.odometer) ?? state.vehicle.odometerKm,
    speedKph: toKph(drive.speed) ?? state.vehicle.speedKph,
    headingDeg: drive.heading ?? state.vehicle.headingDeg,
    isLocked: vehicleState.locked ?? state.vehicle.isLocked,
    isClimateOn: climate.is_climate_on ?? state.vehicle.isClimateOn,
    location: {
      lat: drive.latitude ?? state.vehicle.location.lat,
      lon: drive.longitude ?? state.vehicle.location.lon
    },
    navigation
  };
}

function createFleetApiError(status, parsed, bodyText) {
  const msg = parsed?.error || parsed?.message || bodyText || `HTTP ${status}`;
  const err = new Error(`Fleet API error (${status}): ${msg}`);
  err.status = status;
  err.body = parsed ?? null;
  return err;
}

async function refreshFleetUserTokenOnce(reason) {
  if (fleetUserTokenRefreshInFlight) {
    return fleetUserTokenRefreshInFlight;
  }

  fleetUserTokenRefreshInFlight = (async () => {
    try {
      const refreshed = await refreshFleetUserToken();
      console.log('[fleet-auth] refreshed user token', {
        reason: String(reason || 'unknown'),
        expiresAt: refreshed.expiresAt || null
      });
      return refreshed;
    } finally {
      fleetUserTokenRefreshInFlight = null;
    }
  })();

  return fleetUserTokenRefreshInFlight;
}

async function fetchTeslaJson(pathname, method = 'GET', body = null) {
  if (!TESLA_USER_ACCESS_TOKEN) {
    throw new Error('TESLA_USER_ACCESS_TOKEN is missing.');
  }

  const requestOnce = async () => {
    const url = `${TESLA_FLEET_API_BASE}${pathname}`;
    const res = await fetch(url, {
      method,
      headers: {
        Authorization: `Bearer ${TESLA_USER_ACCESS_TOKEN}`,
        'Content-Type': 'application/json'
      },
      body: body ? JSON.stringify(body) : undefined
    });

    const bodyText = await res.text();
    let parsed;
    try {
      parsed = bodyText ? JSON.parse(bodyText) : {};
    } catch {
      parsed = { raw: bodyText };
    }

    return { res, bodyText, parsed };
  };

  const first = await requestOnce();
  if (first.res.ok) {
    return { parsed: first.parsed, status: first.res.status };
  }

  // Auto refresh token on 401 once, then retry the original request.
  if (first.res.status === 401 && TESLA_USER_REFRESH_TOKEN && TESLA_CLIENT_ID) {
    try {
      await refreshFleetUserTokenOnce(`http401:${method}:${pathname}`);
    } catch (refreshError) {
      const base = createFleetApiError(first.res.status, first.parsed, first.bodyText);
      const refreshMessage = refreshError instanceof Error ? refreshError.message : String(refreshError);
      base.message = `${base.message} | refresh failed: ${refreshMessage}`;
      throw base;
    }

    const retry = await requestOnce();
    if (retry.res.ok) {
      return { parsed: retry.parsed, status: retry.res.status };
    }
    throw createFleetApiError(retry.res.status, retry.parsed, retry.bodyText);
  }

  throw createFleetApiError(first.res.status, first.parsed, first.bodyText);
}

async function fetchTeslaVehicles() {
  const { parsed } = await fetchTeslaJson('/api/1/vehicles', 'GET');
  const list = Array.isArray(parsed?.response) ? parsed.response : [];
  return list
    .map((vehicle) => ({
      id: vehicle.id_s || vehicle.id || null,
      vin: vehicle.vin || '',
      displayName: vehicle.display_name || '',
      state: vehicle.state || 'unknown'
    }))
    .filter((vehicle) => vehicle.vin);
}

async function resolveVehicleVin() {
  const vehicles = await fetchTeslaVehicles();
  const configuredVin = String(runtime.resolvedVin || TESLA_VIN || '').trim();

  let picked = null;
  if (configuredVin) {
    picked = vehicles.find((vehicle) => vehicle.vin === configuredVin) || null;
  }
  if (!picked) {
    picked = vehicles[0] || null;
  }

  if (!picked?.vin) {
    if (configuredVin) {
      runtime.resolvedVin = configuredVin;
      return configuredVin;
    }
    throw new Error('Could not resolve VIN. Set TESLA_VIN or ensure account has accessible vehicles.');
  }

  runtime.resolvedVin = picked.vin;
  runtime.resolvedDisplayName = String(picked.displayName || '').trim();
  applyPatch(
    {
      vin: picked.vin,
      displayName: picked.displayName || state.vehicle.displayName
    },
    'fleet_resolve_vin'
  );
  return picked.vin;
}

async function fetchTeslaVehicleData() {
  const vin = await resolveVehicleVin();
  const { parsed } = await fetchTeslaJson(`/api/1/vehicles/${vin}/vehicle_data`, 'GET');

  const response = parsed?.response || parsed;
  if (!response || typeof response !== 'object') {
    throw new Error('Fleet API response missing data.');
  }

  const next = mapTeslaVehicleDataToSnapshot(response);
  applyPatch(next, 'fleet_poll');
  return snapshotResponse();
}

async function refreshFleetUserToken() {
  if (!TESLA_CLIENT_ID || !TESLA_USER_REFRESH_TOKEN) {
    throw new Error('Missing TESLA_CLIENT_ID or TESLA_USER_REFRESH_TOKEN for auto auth repair.');
  }

  const body = new URLSearchParams();
  body.set('grant_type', 'refresh_token');
  body.set('client_id', TESLA_CLIENT_ID);
  body.set('refresh_token', TESLA_USER_REFRESH_TOKEN);
  if (TESLA_CLIENT_SECRET) {
    body.set('client_secret', TESLA_CLIENT_SECRET);
  }

  const res = await fetch(TESLA_TOKEN_URL, {
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
    throw new Error(`Token refresh failed (${res.status}): ${message}`);
  }

  const accessToken = String(parsed?.access_token || '').trim();
  const nextRefreshToken = String(parsed?.refresh_token || TESLA_USER_REFRESH_TOKEN).trim();
  const expiresIn = Number(parsed?.expires_in || 0);
  const expiresAt = expiresIn > 0 ? new Date(Date.now() + expiresIn * 1000).toISOString() : '';

  if (!accessToken) {
    throw new Error('Token refresh succeeded but access_token is missing.');
  }

  TESLA_USER_ACCESS_TOKEN = accessToken;
  TESLA_USER_REFRESH_TOKEN = nextRefreshToken;
  TESLA_TOKEN_GRANT_TYPE = inferJwtGrantType(TESLA_USER_ACCESS_TOKEN);

  upsertEnvFile(ROOT_ENV_PATH, {
    TESLA_USER_ACCESS_TOKEN: accessToken,
    TESLA_USER_REFRESH_TOKEN: nextRefreshToken,
    TESLA_USER_TOKEN_EXPIRES_AT: expiresAt
  });

  return {
    accessToken,
    refreshToken: nextRefreshToken,
    expiresAt
  };
}

async function forwardTeslaCommand(command, payload = null) {
  if (!TESLA_USER_ACCESS_TOKEN) {
    return {
      ok: false,
      status: 400,
      message: 'TESLA_USER_ACCESS_TOKEN is required for real commands.'
    };
  }

  try {
    const vin = await resolveVehicleVin();

    if (command === 'navigation_request' || command === 'navigation_waypoints_request') {
      const destination = normalizeNavigationDestination(payload);
      if (!destination) {
        return {
          ok: false,
          status: 400,
          message: 'Navigation payload must include destination lat/lon.'
        };
      }

      const commandAttempts = [
        {
          command: 'navigation_waypoints_request',
          body: {
            waypoints: [
              {
                lat: destination.lat,
                lon: destination.lon,
                name: destination.name
              }
            ]
          }
        },
        {
          command: 'navigation_request',
          body: {
            lat: destination.lat,
            lon: destination.lon,
            name: destination.name
          }
        }
      ];

      let last = null;
      for (const attempt of commandAttempts) {
        const path = `/api/1/vehicles/${vin}/command/${encodeURIComponent(attempt.command)}`;
        try {
          const { parsed, status } = await fetchTeslaJson(path, 'POST', attempt.body);
          const summarized = summarizeFleetCommand(parsed, status, `${attempt.command} failed`);
          if (summarized.ok) {
            return {
              ...summarized,
              message: `${summarized.message} (destination: ${destination.name})`
            };
          }
          last = summarized;
        } catch (error) {
          last = {
            ok: false,
            status: Number(error?.status || 0) || 502,
            message: error instanceof Error ? error.message : 'Navigation command failed',
            body: error?.body || null
          };
        }
      }

      return last || {
        ok: false,
        status: 502,
        message: 'Navigation command failed.',
        body: null
      };
    }

    // Fleet API note: wake_up is NOT a /command endpoint.
    const path =
      command === 'wake_up'
        ? `/api/1/vehicles/${vin}/wake_up`
        : `/api/1/vehicles/${vin}/command/${encodeURIComponent(command)}`;

    const commandBody =
      command === 'wake_up'
        ? {}
        : payload && typeof payload === 'object'
          ? payload
          : {};
    const { parsed, status } = await fetchTeslaJson(path, 'POST', commandBody);
    return summarizeFleetCommand(parsed, status);
  } catch (error) {
    return {
      ok: false,
      status: Number(error?.status || 0) || 502,
      message: error instanceof Error ? error.message : 'Fleet command failed',
      body: error?.body || null
    };
  }
}

async function fetchActiveVehicleData() {
  return state.mode === 'fleet' ? fetchTeslaVehicleData() : snapshotResponse();
}

async function route(req, res) {
  if (req.method === 'OPTIONS') {
    sendJson(res, 204, {});
    return;
  }

  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'GET' && STATIC_PAGE_PATHS.has(url.pathname)) {
    try {
      await sendHtmlFile(res, STATIC_PAGE_PATHS.get(url.pathname));
    } catch {
      sendJson(res, 404, { ok: false, message: `Static page not found: ${url.pathname}` });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/health') {
    sendJson(res, 200, {
      ok: true,
      mode: state.mode,
      source: state.source,
      updatedAt: state.updatedAt,
      backendTokenRequired: ENFORCE_BACKEND_API_TOKEN,
      appAuth: {
        enabled: true,
        signupEnabled: true,
        defaultAdminUsername: APP_DEFAULT_ADMIN_USERNAME,
        userCount: appUsersByUsername.size
      }
    });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/auth/login') {
    let payload = {};
    try {
      payload = await readJson(req);
    } catch {
      payload = {};
    }

    const username = normalizeUsername(payload?.username || '');
    const password = String(payload?.password || '');
    if (!username || !password) {
      sendJson(res, 400, { ok: false, message: 'Missing username/password.' });
      return;
    }

    const user = getUserByUsername(username);
    if (!user) {
      sendJson(res, 401, { ok: false, message: 'Invalid credentials.' });
      return;
    }

    const passwordOk = timingSafeEqualString(hashUserPassword(username, password), user.passwordHash);
    if (!passwordOk) {
      sendJson(res, 401, { ok: false, message: 'Invalid credentials.' });
      return;
    }

    const session = issueAppSession({ username: user.username, role: user.role });
    sendJson(res, 200, {
      ok: true,
      sessionToken: session.token,
      expiresAt: session.expiresAt,
      user: toPublicUser(user),
      bootstrap: buildUserBootstrap(req, user)
    });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/auth/signup') {
    let payload = {};
    try {
      payload = await readJson(req);
    } catch {
      payload = {};
    }

    const username = normalizeUsername(payload?.username || '');
    const password = String(payload?.password || '');
    if (!isValidUsername(username)) {
      sendJson(res, 400, { ok: false, message: 'Username must match [a-z0-9._-] and be 3-32 chars.' });
      return;
    }
    if (!isValidPassword(password)) {
      sendJson(res, 400, { ok: false, message: 'Password must be 4-128 chars.' });
      return;
    }
    if (getUserByUsername(username)) {
      sendJson(res, 409, { ok: false, message: 'Username already exists.' });
      return;
    }

    const user = createUserRecord({
      username,
      password,
      role: username === APP_DEFAULT_ADMIN_USERNAME ? 'admin' : 'member'
    });
    appUsersByUsername.set(user.username, user);
    await queuePersistUsers();

    const session = issueAppSession({ username: user.username, role: user.role });
    sendJson(res, 201, {
      ok: true,
      sessionToken: session.token,
      expiresAt: session.expiresAt,
      user: toPublicUser(user),
      bootstrap: buildUserBootstrap(req, user)
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/auth/me') {
    const authz = requireAppSessionOrRespond(req, res);
    if (!authz) {
      return;
    }
    sendJson(res, 200, {
      ok: true,
      user: toPublicUser(authz.user),
      session: {
        createdAt: authz.session.createdAt,
        lastSeenAt: authz.session.lastSeenAt,
        expiresAt: authz.session.expiresAt
      }
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/auth/bootstrap') {
    const authz = requireAppSessionOrRespond(req, res);
    if (!authz) {
      return;
    }
    sendJson(res, 200, {
      ok: true,
      bootstrap: buildUserBootstrap(req, authz.user)
    });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/auth/keys') {
    const authz = requireAppSessionOrRespond(req, res);
    if (!authz) {
      return;
    }

    let payload = {};
    try {
      payload = await readJson(req);
    } catch {
      payload = {};
    }

    const currentTesla = normalizeTeslaSettings(authz.user.settings?.tesla ?? null, defaultTeslaSettingsForUser());
    const currentKakao = normalizeKakaoSettings(authz.user.settings?.kakao ?? null, { restAPIKey: '', javaScriptKey: '' });
    const nextTeslaRequested = normalizeTeslaSettings(payload?.tesla ?? null, currentTesla);
    const nextKakao = normalizeKakaoSettings(payload?.kakao ?? null, currentKakao);
    const nextTesla = authz.user.role === 'admin' ? nextTeslaRequested : currentTesla;

    authz.user.settings = {
      tesla: nextTesla,
      kakao: nextKakao
    };
    authz.user.updatedAt = new Date().toISOString();
    await queuePersistUsers();

    sendJson(res, 200, {
      ok: true,
      user: toPublicUser(authz.user),
      bootstrap: buildUserBootstrap(req, authz.user)
    });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/auth/logout') {
    const authz = requireAppSessionOrRespond(req, res);
    if (!authz) {
      return;
    }
    appSessions.delete(authz.token);
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/vehicle/latest') {
    if (!requireBackendTokenOrRespond(req, res)) {
      return;
    }
    sendJson(res, 200, snapshotResponse());
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/data/speed_cameras_kr') {
    try {
      const stat = await fs.stat(SPEED_CAMERA_DATA_PATH);
      const etag = `"${stat.size}-${Math.floor(stat.mtimeMs)}"`;

      if (req.headers['if-none-match'] === etag) {
        res.writeHead(304, {
          ETag: etag,
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Backend-Token,X-App-Session,X-Api-Key'
        });
        res.end();
        return;
      }

      const raw = await fs.readFile(SPEED_CAMERA_DATA_PATH, 'utf8');
      res.writeHead(200, {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Length': Buffer.byteLength(raw),
        'Cache-Control': 'public, max-age=86400',
        ETag: etag,
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Backend-Token,X-App-Session,X-Api-Key'
      });
      res.end(raw);
    } catch (error) {
      sendJson(res, 404, {
        ok: false,
        message:
          'Speed camera dataset not found on backend. Run backend/scripts/update_speed_cameras_kr.mjs and retry.'
      });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/telemetry/ingest') {
    try {
      const body = await readJson(req);
      const nextVehicle = normalizeIngestPayload(body);
      applyPatch(nextVehicle, 'telemetry_ingest');
      sendJson(res, 200, { ok: true, snapshot: snapshotResponse() });
    } catch (error) {
      sendJson(res, 400, { ok: false, message: error instanceof Error ? error.message : 'Invalid payload' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/tesla/oauth/exchange') {
    const authz = requireBackendToken(req);
    if (!authz.ok) {
      sendJson(res, 401, { ok: false, message: authz.message });
      return;
    }

    let payload = {};
    try {
      payload = await readJson(req);
    } catch {
      payload = {};
    }

    const codeInput = String(payload?.code || payload?.codeInput || payload?.callbackUrl || '').trim();
    if (!codeInput) {
      sendJson(res, 400, { ok: false, message: 'Missing code/callbackUrl.' });
      return;
    }

    const clientId = TESLA_CLIENT_ID;
    const clientSecret = TESLA_CLIENT_SECRET;
    const redirectUri = process.env.TESLA_REDIRECT_URI || '';
    const codeVerifier = process.env.TESLA_CODE_VERIFIER || '';
    const audience = process.env.TESLA_AUDIENCE || TESLA_FLEET_API_BASE;

    if (!clientId || !clientSecret || !redirectUri) {
      sendJson(res, 500, { ok: false, message: 'Server missing TESLA_CLIENT_ID/SECRET/REDIRECT_URI.' });
      return;
    }
    if (!codeVerifier) {
      sendJson(res, 500, { ok: false, message: 'Server missing TESLA_CODE_VERIFIER. Run oauth start first.' });
      return;
    }

    try {
      const exchanged = await exchangeAuthorizationCode({
        codeInput,
        clientId,
        clientSecret,
        redirectUri,
        codeVerifier,
        audience
      });

      const accessToken = exchanged.accessToken;
      const refreshToken = exchanged.refreshToken;
      const expiresAt = exchanged.expiresAt;

      upsertEnvFile(ROOT_ENV_PATH, {
        TESLA_USER_ACCESS_TOKEN: accessToken,
        TESLA_USER_REFRESH_TOKEN: refreshToken || '',
        TESLA_USER_TOKEN_EXPIRES_AT: expiresAt,
        TESLA_OAUTH_STATE: '',
        TESLA_CODE_VERIFIER: ''
      });

      // Update runtime token variables for this process
      TESLA_USER_ACCESS_TOKEN = accessToken;
      TESLA_USER_REFRESH_TOKEN = refreshToken || '';
      TESLA_TOKEN_GRANT_TYPE = inferJwtGrantType(TESLA_USER_ACCESS_TOKEN);

      sendJson(res, 200, {
        ok: true,
        expiresAt,
        note: 'Tokens exchanged and saved server-side. Tokens are not returned by this endpoint.'
      });
    } catch (error) {
      sendJson(res, 502, { ok: false, message: error instanceof Error ? error.message : 'Token exchange failed.' });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/tesla/vehicles') {
    if (!requireBackendTokenOrRespond(req, res)) {
      return;
    }
    if (state.mode !== 'fleet') {
      sendJson(res, 400, { ok: false, message: 'This endpoint is available only in fleet mode.' });
      return;
    }
    try {
      const vehicles = await fetchTeslaVehicles();
      sendJson(res, 200, { ok: true, vehicles });
    } catch (error) {
      sendJson(res, 502, { ok: false, message: error instanceof Error ? error.message : 'Vehicle fetch failed' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/vehicle/command') {
    if (!requireBackendTokenOrRespond(req, res)) {
      return;
    }
    try {
      const body = await readJson(req);
      const command = String(body.command || '').trim();
      const payload =
        body?.payload && typeof body.payload === 'object'
          ? body.payload
          : null;
      if (!command) {
        sendJson(res, 400, { ok: false, message: 'Missing command.' });
        return;
      }

      let result;
      if (state.mode === 'simulator') {
        result = applySimCommand(command);
      } else {
        result = await forwardTeslaCommand(command, payload);
      }

      // Attach routing info for easier debugging.
      result = {
        ...result,
        _routedVia: state.mode === 'simulator' ? 'simulator' : 'fleet'
      };

      state.lastCommand = {
        command,
        ok: result.ok,
        message: result.message,
        at: new Date().toISOString()
      };

      // Return 200 with ok=false for command-level failures so clients can surface
      // the real Fleet reason without collapsing everything into HTTP 502.
      sendJson(res, 200, {
        ok: result.ok,
        message: result.message,
        routedVia: result._routedVia || null,
        upstreamStatus: result.status || null,
        details: result.body || null,
        snapshot: snapshotResponse()
      });
    } catch (error) {
      sendJson(res, 500, { ok: false, message: error instanceof Error ? error.message : 'Command failed' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/tesla/poll-now') {
    if (!requireBackendTokenOrRespond(req, res)) {
      return;
    }
    if (state.mode === 'simulator') {
      sendJson(res, 400, { ok: false, message: 'Server is in simulator mode.' });
      return;
    }
    try {
      const snapshot = await fetchActiveVehicleData();
      sendJson(res, 200, { ok: true, snapshot });
    } catch (error) {
      sendJson(res, 502, { ok: false, message: error instanceof Error ? error.message : 'Poll failed' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/vehicle/poll-now') {
    if (!requireBackendTokenOrRespond(req, res)) {
      return;
    }
    if (state.mode === 'simulator') {
      sendJson(res, 400, { ok: false, message: 'Server is in simulator mode.' });
      return;
    }
    try {
      const snapshot = await fetchActiveVehicleData();
      sendJson(res, 200, { ok: true, snapshot });
    } catch (error) {
      sendJson(res, 502, { ok: false, message: error instanceof Error ? error.message : 'Poll failed' });
    }
    return;
  }

  sendJson(res, 404, {
    ok: false,
    message: `Not found: ${req.method} ${url.pathname}`
  });
}

await initializeAppUsers();

if (USE_SIMULATOR) {
  setInterval(tickSimulator, 1000).unref();
} else if (POLL_ENABLED) {
  setInterval(async () => {
    try {
      await fetchActiveVehicleData();
    } catch (error) {
      console.error('[fleet poll]', error instanceof Error ? error.message : error);
    }
  }, POLL_INTERVAL_MS).unref();
}

setInterval(pruneExpiredAppSessions, 60_000).unref();

const server = http.createServer((req, res) => {
  route(req, res).catch((error) => {
    sendJson(res, 500, {
      ok: false,
      message: error instanceof Error ? error.message : 'Unexpected server error'
    });
  });
});

server.listen(PORT, HOST, () => {
  console.log(`[tesla-subdash-backend] listening on http://${HOST}:${PORT}`);
  console.log(`[tesla-subdash-backend] mode=${state.mode} pollEnabled=${POLL_ENABLED}`);
  console.log(`[tesla-subdash-backend] backendAuth=${ENFORCE_BACKEND_API_TOKEN ? 'required' : 'optional'} token=${BACKEND_API_TOKEN ? 'set' : 'missing'}`);
  console.log(
    `[tesla-subdash-backend] appAuth=enabled signup=on users=${appUsersByUsername.size} defaultAdmin=${APP_DEFAULT_ADMIN_USERNAME} sessionTtlMs=${APP_AUTH_SESSION_TTL_MS}`
  );
  console.log(
    `[tesla-subdash-backend] userToken=${TESLA_USER_ACCESS_TOKEN ? 'set' : 'missing'} configuredVin=${
      TESLA_VIN || '(auto)'
    }`
  );
  if (TESLA_TOKEN_GRANT_TYPE) {
    console.log(`[tesla-subdash-backend] tokenGrantType=${TESLA_TOKEN_GRANT_TYPE}`);
  }

  const lan = listLanIPv4();
  if (lan.length) {
    if (HOST === '0.0.0.0' || HOST === '::') {
      console.log('[tesla-subdash-backend] iPad Backend URL candidates:');
      for (const entry of lan) {
        console.log(`  http://${entry.ip}:${PORT}  (${entry.name})`);
      }
    } else {
      console.log('[tesla-subdash-backend] LAN IPs (for iPad, run with HOST=0.0.0.0):');
      for (const entry of lan) {
        console.log(`  http://${entry.ip}:${PORT}  (${entry.name})`);
      }
    }
  } else {
    console.log('[tesla-subdash-backend] No LAN IPv4 detected (Wi-Fi might be disconnected).');
  }
});
