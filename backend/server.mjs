import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createTeslaMateClient } from './teslamate_client.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

loadEnvFile(path.resolve(__dirname, '../.env'));

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return;
  }

  const raw = fs.readFileSync(filePath, 'utf8');
  const lines = raw.split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }
    const idx = trimmed.indexOf('=');
    if (idx < 0) {
      continue;
    }

    const key = trimmed.slice(0, idx).trim();
    const value = trimmed.slice(idx + 1).trim().replace(/^['"]|['"]$/g, '');
    if (!key) {
      continue;
    }

    if (process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || '127.0.0.1';
const USE_SIMULATOR = process.env.USE_SIMULATOR !== '0';
const DATA_SOURCE = String(process.env.DATA_SOURCE || '').trim().toLowerCase();
const USE_TESLAMATE = DATA_SOURCE === 'teslamate' || process.env.USE_TESLAMATE === '1';
const MODE = USE_SIMULATOR ? 'simulator' : USE_TESLAMATE ? 'teslamate' : 'fleet';
const POLL_ENABLED = process.env.POLL_TESLA === '1' || process.env.POLL_ENABLED === '1';
const POLL_INTERVAL_MS = Number(process.env.POLL_INTERVAL_MS || 8000);
const TESLA_USER_ACCESS_TOKEN = process.env.TESLA_USER_ACCESS_TOKEN || process.env.TESLA_ACCESS_TOKEN || '';
const TESLA_VIN = process.env.TESLA_VIN || '';
const TESLA_FLEET_API_BASE = process.env.TESLA_FLEET_API_BASE || 'https://fleet-api.prd.na.vn.cloud.tesla.com';
const TESLA_TOKEN_GRANT_TYPE = inferJwtGrantType(TESLA_USER_ACCESS_TOKEN);
const TESLAMATE_API_BASE = process.env.TESLAMATE_API_BASE || '';
const TESLAMATE_API_TOKEN = process.env.TESLAMATE_API_TOKEN || '';
const TESLAMATE_CAR_ID = process.env.TESLAMATE_CAR_ID || '';
const TESLAMATE_AUTH_HEADER = process.env.TESLAMATE_AUTH_HEADER || 'Authorization';
const TESLAMATE_TOKEN_QUERY_KEY = process.env.TESLAMATE_TOKEN_QUERY_KEY || '';
const runtime = {
  resolvedVin: TESLA_VIN,
  resolvedTeslaMateCarId: TESLAMATE_CAR_ID || null
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

function sendJson(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization'
  });
  res.end(payload);
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
  const nextVehicle = {
    ...state.vehicle,
    ...patch,
    location: {
      ...state.vehicle.location,
      ...(patch.location || {})
    }
  };

  state.vehicle = nextVehicle;
  state.source = source;
  state.updatedAt = new Date().toISOString();
}

function snapshotResponse() {
  return {
    source: state.source,
    mode: state.mode,
    updatedAt: state.updatedAt,
    lastCommand: state.lastCommand,
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
    default:
      return { ok: false, message: `Unsupported simulated command: ${command}` };
  }
}

function normalizeIngestPayload(payload) {
  const vehicle = payload.vehicle || {};

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
    }
  };
}

function mapTeslaVehicleDataToSnapshot(vehicleData) {
  const drive = vehicleData.drive_state || {};
  const charge = vehicleData.charge_state || {};
  const climate = vehicleData.climate_state || {};
  const vehicleState = vehicleData.vehicle_state || {};

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
    }
  };
}

async function fetchTeslaJson(pathname, method = 'GET', body = null) {
  if (!TESLA_USER_ACCESS_TOKEN) {
    throw new Error('TESLA_USER_ACCESS_TOKEN is missing.');
  }

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

  if (!res.ok) {
    const msg = parsed?.error || parsed?.message || bodyText || `HTTP ${res.status}`;
    throw new Error(`Fleet API error (${res.status}): ${msg}`);
  }

  return { parsed, status: res.status };
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

async function fetchTeslaMateVehicleData() {
  if (!teslaMateClient) {
    throw new Error('TeslaMate mode is not enabled.');
  }

  const result = await teslaMateClient.fetchLatestVehicle(state.vehicle);
  runtime.resolvedTeslaMateCarId = result.carId || runtime.resolvedTeslaMateCarId;
  applyPatch(result.vehicle, 'teslamate_poll');
  return snapshotResponse();
}

async function forwardTeslaCommand(command) {
  if (!TESLA_USER_ACCESS_TOKEN) {
    return {
      ok: false,
      status: 400,
      message: 'TESLA_USER_ACCESS_TOKEN is required for real commands.'
    };
  }

  let parsed;
  let status;
  try {
    const vin = await resolveVehicleVin();
    const result = await fetchTeslaJson(`/api/1/vehicles/${vin}/command/${encodeURIComponent(command)}`, 'POST', {});
    parsed = result.parsed;
    status = result.status;
  } catch (error) {
    return {
      ok: false,
      status: 502,
      message: error instanceof Error ? error.message : 'Fleet command failed',
      body: null
    };
  }

  const result = parsed?.response?.result;
  const success = typeof result === 'boolean' ? result : true;

  return {
    ok: success,
    status,
    message: parsed?.response?.reason || parsed?.error || parsed?.message || (success ? 'OK' : 'Command failed'),
    body: parsed
  };
}

async function forwardTeslaMateCommand(command) {
  if (!teslaMateClient) {
    return {
      ok: false,
      status: 400,
      message: 'TeslaMate mode is not enabled.'
    };
  }

  const result = await teslaMateClient.sendCommand(command);
  if (result.ok) {
    try {
      await fetchTeslaMateVehicleData();
    } catch {
      // Non-fatal: command result is still useful even if refresh fails.
    }
  }

  return result;
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
      tokenGrantType: TESLA_TOKEN_GRANT_TYPE,
      hasTeslaMateBase: !!TESLAMATE_API_BASE,
      hasTeslaMateToken: !!TESLAMATE_API_TOKEN,
      teslaMateAuthHeader: TESLAMATE_AUTH_HEADER,
      source: state.source,
      updatedAt: state.updatedAt
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/api/vehicle/latest') {
    sendJson(res, 200, snapshotResponse());
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

  if (req.method === 'POST' && url.pathname === '/api/vehicle/command') {
    try {
      const body = await readJson(req);
      const command = String(body.command || '').trim();
      if (!command) {
        sendJson(res, 400, { ok: false, message: 'Missing command.' });
        return;
      }

      let result;
      if (state.mode === 'simulator') {
        result = applySimCommand(command);
      } else if (state.mode === 'teslamate') {
        result = await forwardTeslaMateCommand(command);
      } else {
        result = await forwardTeslaCommand(command);
      }

      state.lastCommand = {
        command,
        ok: result.ok,
        message: result.message,
        at: new Date().toISOString()
      };

      sendJson(res, result.ok ? 200 : 502, {
        ok: result.ok,
        message: result.message,
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
