import fs from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnvFile, upsertEnvFile } from './env.mjs';
import { createTeslaMateClient } from './teslamate_client.mjs';
import { syncTokensToTeslaMateRuntime } from './teslamate_token_bridge.mjs';
import { exchangeAuthorizationCode } from './tesla_oauth_common.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT_ENV_PATH = path.resolve(__dirname, '../.env');

loadEnvFile(ROOT_ENV_PATH);

const SPEED_CAMERA_DATA_PATH = path.resolve(
  __dirname,
  process.env.SPEED_CAMERA_DATA_PATH || './data/speed_cameras_kr.min.json'
);

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || '127.0.0.1';
const USE_SIMULATOR = process.env.USE_SIMULATOR !== '0';
const DATA_SOURCE = String(process.env.DATA_SOURCE || '').trim().toLowerCase();
const USE_TESLAMATE = DATA_SOURCE === 'teslamate' || process.env.USE_TESLAMATE === '1';
const MODE = USE_SIMULATOR ? 'simulator' : USE_TESLAMATE ? 'teslamate' : 'fleet';
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
const TESLAMATE_API_BASE = process.env.TESLAMATE_API_BASE || 'http://127.0.0.1:8080';
const TESLAMATE_API_TOKEN = process.env.TESLAMATE_API_TOKEN || '';
const TESLAMATE_CAR_ID = process.env.TESLAMATE_CAR_ID || '';
const TESLAMATE_AUTH_HEADER = process.env.TESLAMATE_AUTH_HEADER || 'Authorization';
const TESLAMATE_TOKEN_QUERY_KEY = process.env.TESLAMATE_TOKEN_QUERY_KEY || '';
const TESLAMATE_CONTAINER_NAME = process.env.TESLAMATE_CONTAINER_NAME || 'teslamate-stack-teslamate-1';
const BACKEND_API_TOKEN = process.env.BACKEND_API_TOKEN || '';
const TESLAMATE_SYNC_ON_EXCHANGE = process.env.TESLAMATE_SYNC_ON_EXCHANGE !== '0';
const TESLAMATE_AUTO_AUTH_REPAIR = process.env.TESLAMATE_AUTO_AUTH_REPAIR !== '0';
const TESLAMATE_AUTH_REPAIR_COOLDOWN_MS = Math.max(10_000, Number(process.env.TESLAMATE_AUTH_REPAIR_COOLDOWN_MS || 180_000));
const TESLAMATE_AUTH_REPAIR_SETTLE_MS = Math.max(1_000, Number(process.env.TESLAMATE_AUTH_REPAIR_SETTLE_MS || 3_000));
const runtime = {
  resolvedVin: TESLA_VIN,
  resolvedTeslaMateCarId: TESLAMATE_CAR_ID || null,
  authRepair: {
    inFlight: false,
    lastAttemptAt: null,
    lastSuccessAt: null,
    lastReason: null,
    lastError: null
  }
};

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
    vin: MODE === 'fleet' ? TESLA_VIN || 'FLEET_VIN' : MODE === 'teslamate' ? 'TESLAMATE_VIN' : 'SIMULATED_VIN',
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

let teslaMateClient = null;
if (state.mode === 'teslamate') {
  teslaMateClient = createTeslaMateClient({
    baseURL: TESLAMATE_API_BASE,
    token: TESLAMATE_API_TOKEN,
    explicitCarId: TESLAMATE_CAR_ID,
    authHeader: TESLAMATE_AUTH_HEADER,
    tokenQueryKey: TESLAMATE_TOKEN_QUERY_KEY
  });
}

let teslaMateAuthRepairInFlight = null;
let fleetUserTokenRefreshInFlight = null;

function sendJson(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Backend-Token'
  });
  res.end(payload);
}

function requireBackendToken(req) {
  if (!BACKEND_API_TOKEN) {
    return { ok: true };
  }
  const header = String(req.headers['x-backend-token'] || '').trim();
  const auth = String(req.headers.authorization || '').trim();
  const bearer = auth.toLowerCase().startsWith('bearer ') ? auth.slice(7).trim() : '';

  if (header === BACKEND_API_TOKEN || bearer === BACKEND_API_TOKEN) {
    return { ok: true };
  }
  return { ok: false, message: 'Unauthorized (missing/invalid backend token).' };
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
  if (runtime.resolvedVin) {
    return runtime.resolvedVin;
  }

  const vehicles = await fetchTeslaVehicles();
  const picked = vehicles[0];
  if (!picked?.vin) {
    throw new Error('Could not resolve VIN. Set TESLA_VIN or ensure account has accessible vehicles.');
  }

  runtime.resolvedVin = picked.vin;
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

async function fetchTeslaMateCars() {
  if (!teslaMateClient) {
    throw new Error('TeslaMate mode is not enabled.');
  }
  return teslaMateClient.fetchCars();
}

function isLikelyTeslaMateAuthFailure(error) {
  const status = Number(error?.status || 0);
  if (status === 401 || status === 403) {
    return true;
  }

  const text = String(error?.message || '').toLowerCase();
  if (!text) {
    return false;
  }

  return (
    text.includes('returned no cars') ||
    text.includes('not signed in') ||
    text.includes('not_signed_in') ||
    text.includes('unauthorized') ||
    text.includes('forbidden') ||
    text.includes('token') ||
    text.includes('authentication')
  );
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

async function attemptTeslaMateAuthRepair(reason, { force = false } = {}) {
  if (!TESLAMATE_AUTO_AUTH_REPAIR) {
    return { ok: false, skipped: 'disabled', message: 'TESLAMATE_AUTO_AUTH_REPAIR=0' };
  }

  const now = Date.now();
  const lastAttemptAtMs = runtime.authRepair.lastAttemptAt ? Date.parse(runtime.authRepair.lastAttemptAt) : 0;
  if (!force && lastAttemptAtMs && now - lastAttemptAtMs < TESLAMATE_AUTH_REPAIR_COOLDOWN_MS) {
    return {
      ok: false,
      skipped: 'cooldown',
      waitMs: TESLAMATE_AUTH_REPAIR_COOLDOWN_MS - (now - lastAttemptAtMs),
      message: 'Auth repair is cooling down.'
    };
  }

  if (teslaMateAuthRepairInFlight) {
    return teslaMateAuthRepairInFlight;
  }

  runtime.authRepair.inFlight = true;
  runtime.authRepair.lastAttemptAt = new Date().toISOString();
  runtime.authRepair.lastReason = String(reason || 'unknown');

  teslaMateAuthRepairInFlight = (async () => {
    try {
      const refreshed = await refreshFleetUserToken();
      const sync = syncTokensToTeslaMateRuntime({
        accessToken: refreshed.accessToken,
        refreshToken: refreshed.refreshToken,
        containerName: TESLAMATE_CONTAINER_NAME
      });

      // TeslaMate may need a short delay before cars/status endpoints recover.
      await wait(TESLAMATE_AUTH_REPAIR_SETTLE_MS);

      runtime.authRepair.lastSuccessAt = new Date().toISOString();
      runtime.authRepair.lastError = null;

      return {
        ok: true,
        refreshedAt: runtime.authRepair.lastSuccessAt,
        expiresAt: refreshed.expiresAt,
        syncOutput: sync?.stdout || null
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      runtime.authRepair.lastError = message;
      return {
        ok: false,
        message
      };
    } finally {
      runtime.authRepair.inFlight = false;
      teslaMateAuthRepairInFlight = null;
    }
  })();

  return teslaMateAuthRepairInFlight;
}

async function fetchTeslaMateVehicleData() {
  if (!teslaMateClient) {
    throw new Error('TeslaMate mode is not enabled.');
  }

  try {
    const result = await teslaMateClient.fetchLatestVehicle(state.vehicle);
    runtime.resolvedTeslaMateCarId = result.carId || runtime.resolvedTeslaMateCarId;
    applyPatch(result.vehicle, 'teslamate_poll');
    return snapshotResponse();
  } catch (error) {
    if (!isLikelyTeslaMateAuthFailure(error)) {
      throw error;
    }

    const repaired = await attemptTeslaMateAuthRepair(error instanceof Error ? error.message : 'unknown error');
    if (!repaired.ok) {
      if (repaired.skipped === 'cooldown') {
        const seconds = Math.max(1, Math.ceil(Number(repaired.waitMs || 0) / 1000));
        throw new Error(
          `${error instanceof Error ? error.message : 'TeslaMate fetch failed.'} (auto-repair cooldown ${seconds}s)`
        );
      }
      throw new Error(
        `${error instanceof Error ? error.message : 'TeslaMate fetch failed.'} | auto-repair failed: ${
          repaired.message || 'unknown'
        }`
      );
    }

    const retry = await teslaMateClient.fetchLatestVehicle(state.vehicle);
    runtime.resolvedTeslaMateCarId = retry.carId || runtime.resolvedTeslaMateCarId;
    applyPatch(retry.vehicle, 'teslamate_poll');
    return snapshotResponse();
  }
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

async function forwardTeslaMateCommand(command) {
  if (!teslaMateClient) {
    return {
      ok: false,
      status: 400,
      message: 'TeslaMate mode is not enabled.'
    };
  }

  const candidates = teslaMateCommandCandidates(command);
  let lastResult = null;

  for (const candidate of candidates) {
    const result = await teslaMateClient.sendCommand(candidate);
    lastResult = result;
    if (result.ok) {
      try {
        await fetchTeslaMateVehicleData();
      } catch {
        // Non-fatal: command result is still useful even if refresh fails.
      }

      const suffix = candidate === command ? '' : ` (mapped from ${command} -> ${candidate})`;
      return {
        ...result,
        message: `${result.message}${suffix}`
      };
    }

    if (!isLikelyUnsupportedTeslaMateCommand(result)) {
      return result;
    }
  }

  return lastResult || {
    ok: false,
    status: 502,
    message: `TeslaMate command failed: ${command}`
  };
}

function isLikelyUnsupportedTeslaMateCommand(result) {
  const status = Number(result?.status || 0);
  if (status === 404) {
    return true;
  }
  const text = String(result?.message || '').toLowerCase();
  return (
    text.includes('not found') ||
    text.includes('unsupported') ||
    text.includes('unknown command') ||
    text.includes('invalid command')
  );
}

function teslaMateCommandCandidates(command) {
  const normalized = String(command || '').trim();
  switch (normalized) {
    case 'door_lock':
    case 'lock':
      return ['door_lock', 'lock'];
    case 'door_unlock':
    case 'unlock':
      return ['door_unlock', 'unlock'];
    case 'auto_conditioning_start':
    case 'climate_on':
      return ['auto_conditioning_start', 'climate_on'];
    case 'auto_conditioning_stop':
    case 'climate_off':
      return ['auto_conditioning_stop', 'climate_off'];
    case 'wake_up':
      return ['wake_up'];
    default:
      return [normalized];
  }
}

async function fetchActiveVehicleData() {
  if (state.mode === 'fleet') {
    return fetchTeslaVehicleData();
  }
  if (state.mode === 'teslamate') {
    return fetchTeslaMateVehicleData();
  }
  return snapshotResponse();
}

async function route(req, res) {
  if (req.method === 'OPTIONS') {
    sendJson(res, 204, {});
    return;
  }

  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'GET' && url.pathname === '/health') {
    sendJson(res, 200, {
      ok: true,
      mode: state.mode,
      host: HOST,
      configuredVin: TESLA_VIN || null,
      resolvedVin: runtime.resolvedVin || null,
      resolvedTeslaMateCarId: runtime.resolvedTeslaMateCarId || null,
      hasUserAccessToken: !!TESLA_USER_ACCESS_TOKEN,
      hasUserRefreshToken: !!TESLA_USER_REFRESH_TOKEN,
      tokenGrantType: TESLA_TOKEN_GRANT_TYPE,
      hasTeslaMateBase: !!TESLAMATE_API_BASE,
      hasTeslaMateToken: !!TESLAMATE_API_TOKEN,
      teslaMateAuthHeader: TESLAMATE_AUTH_HEADER,
      teslaMateAutoAuthRepair: TESLAMATE_AUTO_AUTH_REPAIR,
      teslaMateAuthRepairCooldownMs: TESLAMATE_AUTH_REPAIR_COOLDOWN_MS,
      teslaMateAuthRepairSettleMs: TESLAMATE_AUTH_REPAIR_SETTLE_MS,
      teslaMateAuthRepairState: runtime.authRepair,
      source: state.source,
      updatedAt: state.updatedAt
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/vehicle/latest') {
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
          'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Backend-Token'
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
        'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Backend-Token'
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

      let sync = { ok: false, skipped: true, message: 'Skipped' };
      if (TESLAMATE_SYNC_ON_EXCHANGE && refreshToken) {
        try {
          const rpc = syncTokensToTeslaMateRuntime({
            accessToken,
            refreshToken,
            containerName: TESLAMATE_CONTAINER_NAME
          });
          sync = { ok: true, skipped: false, message: 'Synced to TeslaMate runtime', rpc: rpc?.stdout || '' };
        } catch (error) {
          sync = {
            ok: false,
            skipped: false,
            message: error instanceof Error ? error.message : 'TeslaMate runtime sync failed.'
          };
        }
      }

      sendJson(res, 200, {
        ok: true,
        expiresAt,
        syncedTeslaMateRuntime: sync.ok,
        sync,
        note: 'Tokens exchanged and saved server-side. Tokens are not returned by this endpoint.'
      });
    } catch (error) {
      sendJson(res, 502, { ok: false, message: error instanceof Error ? error.message : 'Token exchange failed.' });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/tesla/vehicles') {
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

  if (req.method === 'GET' && url.pathname === '/api/teslamate/cars') {
    if (state.mode !== 'teslamate') {
      sendJson(res, 400, { ok: false, message: 'Server is not in teslamate mode.' });
      return;
    }
    try {
      const cars = await fetchTeslaMateCars();
      sendJson(res, 200, { ok: true, cars });
    } catch (error) {
      sendJson(res, 502, { ok: false, message: error instanceof Error ? error.message : 'TeslaMate cars fetch failed' });
    }
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/teslamate/status') {
    if (state.mode !== 'teslamate') {
      sendJson(res, 400, { ok: false, message: 'Server is not in teslamate mode.' });
      return;
    }
    try {
      const diagnostics = await teslaMateClient.diagnostics();
      sendJson(res, 200, { ok: true, diagnostics, snapshot: snapshotResponse() });
    } catch (error) {
      sendJson(res, 502, { ok: false, message: error instanceof Error ? error.message : 'TeslaMate status failed' });
    }
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/teslamate/repair-auth') {
    if (state.mode !== 'teslamate') {
      sendJson(res, 400, { ok: false, message: 'Server is not in teslamate mode.' });
      return;
    }
    let payload = {};
    try {
      payload = await readJson(req);
    } catch {
      payload = {};
    }

    const force = payload?.force !== false;
    const reason = String(payload?.reason || 'manual').trim() || 'manual';
    const repair = await attemptTeslaMateAuthRepair(`manual:${reason}`, { force });

    if (repair.ok) {
      try {
        await fetchTeslaMateVehicleData();
      } catch {
        // Non-fatal: repair result is still meaningful for ops.
      }
    }

    const statusCode = repair.ok || repair.skipped ? 200 : 502;
    sendJson(res, statusCode, {
      ok: repair.ok,
      repair,
      snapshot: snapshotResponse(),
      authRepairState: runtime.authRepair
    });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/vehicle/command') {
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

      // In teslamate mode we want telemetry (location etc.) from TeslaMate,
      // but vehicle controls (lock/unlock/climate/wake) may not be supported by the TeslaMate API wrapper.
      // Also, even for non-owner setups, Fleet API can still allow driver-level commands.
      const CONTROL_COMMANDS_VIA_FLEET = new Set([
        'door_lock',
        'door_unlock',
        'auto_conditioning_start',
        'auto_conditioning_stop',
        'wake_up',
        'navigation_request',
        'navigation_waypoints_request'
      ]);

      const useFleetForCommand = state.mode === 'teslamate' && CONTROL_COMMANDS_VIA_FLEET.has(command);

      let result;
      if (state.mode === 'simulator') {
        result = applySimCommand(command);
      } else if (state.mode === 'teslamate') {
        result = useFleetForCommand ? await forwardTeslaCommand(command, payload) : await forwardTeslaMateCommand(command);
      } else {
        result = await forwardTeslaCommand(command, payload);
      }

      // Attach routing info for easier debugging.
      result = {
        ...result,
        _routedVia: state.mode === 'simulator' ? 'simulator' : state.mode === 'teslamate' ? (useFleetForCommand ? 'fleet' : 'teslamate') : 'fleet'
      };

      state.lastCommand = {
        command,
        ok: result.ok,
        message: result.message,
        at: new Date().toISOString()
      };

      // Return 200 with ok=false for command-level failures so clients can surface
      // the real Fleet/TeslaMate reason without collapsing everything into HTTP 502.
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

if (USE_SIMULATOR) {
  setInterval(tickSimulator, 1000).unref();
} else if (POLL_ENABLED) {
  setInterval(async () => {
    try {
      await fetchActiveVehicleData();
    } catch (error) {
      const label = state.mode === 'teslamate' ? 'teslamate poll' : 'fleet poll';
      console.error(`[${label}]`, error instanceof Error ? error.message : error);
    }
  }, POLL_INTERVAL_MS).unref();
}

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
  console.log(
    `[tesla-subdash-backend] userToken=${TESLA_USER_ACCESS_TOKEN ? 'set' : 'missing'} configuredVin=${
      TESLA_VIN || '(auto)'
    }`
  );
  if (state.mode === 'teslamate') {
    console.log(
      `[tesla-subdash-backend] teslamateBase=${TESLAMATE_API_BASE || '(missing)'} token=${
        TESLAMATE_API_TOKEN ? 'set' : 'missing'
      } carId=${TESLAMATE_CAR_ID || '(auto)'}`
    );
    console.log(
      `[tesla-subdash-backend] teslamateAutoAuthRepair=${
        TESLAMATE_AUTO_AUTH_REPAIR ? 'on' : 'off'
      } cooldownMs=${TESLAMATE_AUTH_REPAIR_COOLDOWN_MS} settleMs=${TESLAMATE_AUTH_REPAIR_SETTLE_MS}`
    );
  }
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
