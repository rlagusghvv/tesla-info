const DEFAULT_CAR_PATHS = ['/api/v1/cars', '/cars', '/api/cars'];
const DEFAULT_STATUS_PATHS = ['/api/v1/cars/{carId}/status', '/cars/{carId}/status', '/api/cars/{carId}/status'];
const DEFAULT_COMMAND_PATHS = [
  '/api/v1/cars/{carId}/command/{command}',
  '/cars/{carId}/command/{command}',
  '/api/cars/{carId}/command/{command}'
];
const DEFAULT_WAKE_PATHS = ['/api/v1/cars/{carId}/wake_up', '/cars/{carId}/wake_up', '/api/cars/{carId}/wake_up'];

export function createTeslaMateClient(options) {
  const baseURL = String(options?.baseURL || '').trim();
  if (!baseURL) {
    throw new Error('TESLAMATE_API_BASE is missing.');
  }

  const token = String(options?.token || '').trim();
  const authHeader = String(options?.authHeader || 'Authorization').trim() || 'Authorization';
  const tokenQueryKey = String(options?.tokenQueryKey || '').trim();

  const normalizedBase = baseURL.replace(/\/+$/, '');
  let resolvedCarId = options?.explicitCarId ? String(options.explicitCarId) : '';

  const selectedPaths = {
    cars: '',
    status: '',
    command: '',
    wake: ''
  };

  async function request(path, requestOptions = {}) {
    const relative = String(path || '').startsWith('/') ? String(path || '') : `/${String(path || '')}`;
    const base = `${normalizedBase}/`;
    const url = new URL(relative.replace(/^\//, ''), base);

    if (token && tokenQueryKey) {
      url.searchParams.set(tokenQueryKey, token);
    }

    const headers = {
      Accept: 'application/json'
    };
    if (requestOptions.body !== undefined) {
      headers['Content-Type'] = 'application/json';
    }
    if (token) {
      const headerName = authHeader;
      if (headerName.toLowerCase() === 'authorization' && !/^bearer /i.test(token)) {
        headers[headerName] = `Bearer ${token}`;
      } else {
        headers[headerName] = token;
      }
    }

    const res = await fetch(url, {
      method: requestOptions.method || 'GET',
      headers,
      body: requestOptions.body !== undefined ? JSON.stringify(requestOptions.body) : undefined
    });

    const text = await res.text();
    let parsed;
    try {
      parsed = text ? JSON.parse(text) : {};
    } catch {
      parsed = { raw: text };
    }

    if (!res.ok) {
      const details = extractMessage(parsed) || text || `HTTP ${res.status}`;
      const error = new Error(`TeslaMate API error (${res.status}): ${details}`);
      error.status = res.status;
      error.body = parsed;
      error.rawText = text;
      throw error;
    }

    return {
      status: res.status,
      parsed,
      rawText: text,
      url: url.toString()
    };
  }

  async function requestWithFallback(paths, options = {}, selectedPathKey = '') {
    const candidates = [];
    const remembered = selectedPathKey ? selectedPaths[selectedPathKey] : '';
    if (remembered) {
      candidates.push(remembered);
    }
    for (const path of paths) {
      if (!candidates.includes(path)) {
        candidates.push(path);
      }
    }

    let lastError = null;
    for (const candidate of candidates) {
      try {
        const result = await request(candidate, options);
        if (selectedPathKey) {
          selectedPaths[selectedPathKey] = candidate;
        }
        return { ...result, path: candidate };
      } catch (error) {
        lastError = error;
      }
    }

    throw lastError || new Error('TeslaMate API request failed.');
  }

  async function fetchCars() {
    const { parsed } = await requestWithFallback(DEFAULT_CAR_PATHS, {}, 'cars');
    const list = asArrayPayload(parsed);

    return list
      .map((item) => {
        const idValue = firstDefined(item, ['id', 'car_id', 'vehicle_id', 'id_s']);
        const vin = asString(firstDefined(item, ['vin']));
        const displayName = asString(firstDefined(item, ['display_name', 'name', 'car_name'])) || '';
        const state = asString(firstDefined(item, ['state', 'status'])) || 'unknown';
        if (idValue === undefined && !vin) {
          return null;
        }

        return {
          id: idValue === undefined ? null : String(idValue),
          vin: vin || '',
          displayName,
          state
        };
      })
      .filter(Boolean);
  }

  async function resolveCarId() {
    if (resolvedCarId) {
      return resolvedCarId;
    }

    const cars = await fetchCars();
    const first = cars[0];
    if (!first) {
      throw new Error('TeslaMate API returned no cars.');
    }

    resolvedCarId = first.id || first.vin;
    if (!resolvedCarId) {
      throw new Error('Could not resolve TeslaMate car id.');
    }
    return resolvedCarId;
  }

  async function fetchStatusRaw() {
    const carId = await resolveCarId();
    const statusPaths = DEFAULT_STATUS_PATHS.map((template) => template.replace('{carId}', encodeURIComponent(carId)));
    const result = await requestWithFallback(statusPaths, {}, 'status');
    const payload = asObjectPayload(result.parsed);
    return {
      carId,
      payload,
      statusPath: result.path
    };
  }

  async function fetchLatestVehicle(previousVehicle) {
    const { carId, payload } = await fetchStatusRaw();
    const nextVehicle = mapStatusToVehicle(payload, previousVehicle);
    return {
      carId,
      vehicle: nextVehicle
    };
  }

  async function sendCommand(command) {
    const carId = await resolveCarId();
    const isWake = command === 'wake_up';
    const templates = isWake ? DEFAULT_WAKE_PATHS : DEFAULT_COMMAND_PATHS;
    const paths = templates.map((template) =>
      template.replace('{carId}', encodeURIComponent(carId)).replace('{command}', encodeURIComponent(command))
    );

    try {
      const result = await requestWithFallback(paths, { method: 'POST', body: {} }, isWake ? 'wake' : 'command');
      const info = parseCommandResult(result.parsed, command);
      return {
        ok: info.ok,
        status: result.status,
        message: info.message,
        body: result.parsed
      };
    } catch (error) {
      return {
        ok: false,
        status: Number(error?.status) || 502,
        message: error instanceof Error ? error.message : 'TeslaMate command failed.',
        body: error?.body || null
      };
    }
  }

  async function diagnostics() {
    const cars = await fetchCars();
    const status = await fetchStatusRaw();
    const keys = Object.keys(status.payload || {}).sort();
    return {
      carsCount: cars.length,
      resolvedCarId: status.carId,
      statusPath: status.statusPath,
      statusKeys: keys
    };
  }

  return {
    fetchCars,
    fetchLatestVehicle,
    sendCommand,
    diagnostics
  };
}

function mapStatusToVehicle(payload, previousVehicle = null) {
  const prev = previousVehicle || {};
  const lengthUnit = resolveLengthUnit(payload);

  const lat = asNumber(firstDefined(payload, ['latitude', 'lat', 'native_latitude']));
  const lon = asNumber(firstDefined(payload, ['longitude', 'lon', 'lng', 'native_longitude']));
  const location = {
    lat: Number.isFinite(lat) ? lat : Number(prev?.location?.lat ?? 0),
    lon: Number.isFinite(lon) ? lon : Number(prev?.location?.lon ?? 0)
  };

  const speedKphDirect = asNumber(firstDefined(payload, ['speed_kph']));
  const speedRaw = asNumber(firstDefined(payload, ['speed']));
  const speedMph = asNumber(firstDefined(payload, ['speed_mph']));
  const speedFromRaw = Number.isFinite(speedRaw) ? (lengthUnit === 'mi' ? speedRaw * 1.60934 : speedRaw) : NaN;
  const speedKph = Number.isFinite(speedKphDirect)
    ? speedKphDirect
    : Number.isFinite(speedFromRaw)
    ? speedFromRaw
    : Number.isFinite(speedMph)
    ? speedMph * 1.60934
    : Number(prev?.speedKph ?? 0);

  const rangeKm = resolveRangeKm(payload, lengthUnit);
  const odometerKm = resolveOdometerKm(payload, prev, lengthUnit);

  return {
    vin: asString(firstDefined(payload, ['vin'])) || prev?.vin || 'TESLAMATE_VIN',
    displayName: asString(firstDefined(payload, ['display_name', 'name', 'car_name'])) || prev?.displayName || 'Model Y',
    onlineState: asString(firstDefined(payload, ['state', 'online_state', 'status'])) || prev?.onlineState || 'unknown',
    batteryLevel: fallbackNumber(firstDefined(payload, ['battery_level']), prev?.batteryLevel, 0),
    usableBatteryLevel: fallbackNumber(firstDefined(payload, ['usable_battery_level']), prev?.usableBatteryLevel, 0),
    estimatedRangeKm: Number.isFinite(rangeKm) ? rangeKm : Number(prev?.estimatedRangeKm ?? 0),
    insideTempC: fallbackNumber(firstDefined(payload, ['inside_temp', 'inside_temperature']), prev?.insideTempC, 0),
    outsideTempC: fallbackNumber(firstDefined(payload, ['outside_temp', 'outside_temperature']), prev?.outsideTempC, 0),
    odometerKm,
    speedKph,
    headingDeg: fallbackNumber(firstDefined(payload, ['heading']), prev?.headingDeg, 0),
    isLocked: fallbackBool(firstDefined(payload, ['locked', 'is_locked']), prev?.isLocked, true),
    isClimateOn: fallbackBool(firstDefined(payload, ['is_climate_on', 'climate_on']), prev?.isClimateOn, false),
    location
  };
}

function resolveRangeKm(payload, lengthUnit) {
  const km = asNumber(
    firstDefined(payload, ['ideal_battery_range_km', 'est_battery_range_km', 'battery_range_km', 'range_km'])
  );
  if (Number.isFinite(km)) {
    return km;
  }

  const raw = asNumber(firstDefined(payload, ['battery_range', 'ideal_battery_range', 'est_battery_range']));
  if (Number.isFinite(raw)) {
    return lengthUnit === 'mi' ? raw * 1.60934 : raw;
  }

  return NaN;
}

function resolveOdometerKm(payload, previous, lengthUnit) {
  const km = asNumber(firstDefined(payload, ['odometer_km']));
  if (Number.isFinite(km)) {
    return km;
  }

  const raw = asNumber(firstDefined(payload, ['odometer']));
  if (Number.isFinite(raw)) {
    return lengthUnit === 'mi' ? raw * 1.60934 : raw;
  }

  return Number(previous?.odometerKm ?? 0);
}

function resolveLengthUnit(payload) {
  const unit = asString(firstDefined(payload, ['unit_of_length', 'length_unit', 'distance_unit'])).toLowerCase();
  if (unit.startsWith('mi')) {
    return 'mi';
  }
  if (unit.startsWith('km')) {
    return 'km';
  }
  // Default to km because TeslaMate status usually carries already-normalized values by user unit.
  return 'km';
}

function parseCommandResult(parsed, command) {
  const resultBool = asBool(firstDefined(parsed, ['result', 'ok', 'success']));
  const reason =
    asString(firstDefined(parsed, ['reason', 'message', 'error_description', 'error'])) ||
    (resultBool === false ? `${command} failed.` : `${command} requested.`);

  if (resultBool === false) {
    return { ok: false, message: reason };
  }
  if (resultBool === true) {
    return { ok: true, message: reason };
  }

  const errorText = asString(firstDefined(parsed, ['error']));
  if (errorText) {
    return { ok: false, message: errorText };
  }

  return { ok: true, message: reason };
}

function asArrayPayload(parsed) {
  if (Array.isArray(parsed)) {
    return parsed;
  }
  if (!parsed || typeof parsed !== 'object') {
    return [];
  }

  const keys = ['response', 'results', 'data', 'cars', 'items'];
  for (const key of keys) {
    if (Array.isArray(parsed[key])) {
      return parsed[key];
    }
  }

  if (Array.isArray(parsed.response?.cars)) {
    return parsed.response.cars;
  }
  if (Array.isArray(parsed.data?.cars)) {
    return parsed.data.cars;
  }
  if (Array.isArray(parsed.data?.items)) {
    return parsed.data.items;
  }
  if (Array.isArray(parsed.response?.data?.cars)) {
    return parsed.response.data.cars;
  }

  return [];
}

function asObjectPayload(parsed) {
  if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
    if (parsed.response && typeof parsed.response === 'object' && !Array.isArray(parsed.response)) {
      return parsed.response;
    }
    if (parsed.data && typeof parsed.data === 'object' && !Array.isArray(parsed.data)) {
      return parsed.data;
    }
    return parsed;
  }
  return {};
}

function extractMessage(parsed) {
  const value = firstDefined(parsed, ['message', 'error_description', 'error', 'reason']);
  return asString(value);
}

function firstDefined(node, keys) {
  for (const key of keys) {
    const value = findByKey(node, key);
    if (value !== undefined && value !== null) {
      return value;
    }
  }
  return undefined;
}

function findByKey(node, key) {
  if (node === null || node === undefined) {
    return undefined;
  }

  if (Array.isArray(node)) {
    for (const item of node) {
      const value = findByKey(item, key);
      if (value !== undefined) {
        return value;
      }
    }
    return undefined;
  }

  if (typeof node !== 'object') {
    return undefined;
  }

  if (Object.prototype.hasOwnProperty.call(node, key)) {
    return node[key];
  }

  for (const value of Object.values(node)) {
    const found = findByKey(value, key);
    if (found !== undefined) {
      return found;
    }
  }

  return undefined;
}

function asString(value) {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed.length ? trimmed : '';
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }
  return '';
}

function asNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return NaN;
}

function fallbackNumber(value, previous, fallback) {
  const number = asNumber(value);
  if (Number.isFinite(number)) {
    return number;
  }
  const prevNumber = asNumber(previous);
  if (Number.isFinite(prevNumber)) {
    return prevNumber;
  }
  return fallback;
}

function asBool(value) {
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'number') {
    return value !== 0;
  }
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (['true', '1', 'yes', 'on'].includes(normalized)) {
      return true;
    }
    if (['false', '0', 'no', 'off'].includes(normalized)) {
      return false;
    }
  }
  return null;
}

function fallbackBool(value, previous, fallback) {
  const parsed = asBool(value);
  if (parsed !== null) {
    return parsed;
  }
  const prev = asBool(previous);
  if (prev !== null) {
    return prev;
  }
  return fallback;
}
