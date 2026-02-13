#!/usr/bin/env node
/**
 * Fetch Korea unmanned traffic camera dataset from data.go.kr OpenAPI and write a compact JSON file.
 *
 * Usage:
 *   DATA_GO_KR_SERVICE_KEY="..." node backend/scripts/update_speed_cameras_kr.mjs
 *
 * Notes:
 * - data.go.kr service keys are often already URL-encoded. Do NOT double-encode them.
 * - Output file is consumed by backend/server.mjs at /api/data/speed_cameras_kr
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, '..');

const SERVICE_KEY_RAW = String(process.env.DATA_GO_KR_SERVICE_KEY || '').trim();
if (!SERVICE_KEY_RAW) {
  console.error('Missing env: DATA_GO_KR_SERVICE_KEY');
  process.exit(1);
}

const API_BASE =
  String(process.env.DATA_GO_KR_CAMERA_API_BASE || '').trim() ||
  // data.go.kr often redirects api.data.go.kr -> www.api.data.go.kr. Use the final host to avoid surprises.
  'https://www.api.data.go.kr/openapi/tn_pubr_public_unmanned_traffic_camera_api';
const NUM_OF_ROWS = Math.min(1000, Math.max(100, Number(process.env.NUM_OF_ROWS || 1000)));
const OUT_PATH =
  String(process.env.OUT_PATH || '').trim() ||
  path.resolve(ROOT, 'data/speed_cameras_kr.min.json');

function serviceKeyForQuery(raw) {
  const key = String(raw || '').trim();
  if (!key) {
    return '';
  }

  // data.go.kr shows both "인증키(Encoding)" (already URL-encoded) and "인증키(Decoding)" (raw).
  // Accept either:
  // - If it already contains percent-escapes, assume it is encoded and keep as-is.
  // - Otherwise URL-encode it (important because '+' and '/' in the raw key must be encoded).
  if (/%[0-9A-Fa-f]{2}/.test(key)) {
    return key;
  }
  return encodeURIComponent(key);
}

const SERVICE_KEY_QS = serviceKeyForQuery(SERVICE_KEY_RAW);

function buildURL(pageNo) {
  // NOTE: Append serviceKey as query-safe string. Do NOT double-encode.
  const qs = [
    `serviceKey=${SERVICE_KEY_QS}`,
    `pageNo=${pageNo}`,
    `numOfRows=${NUM_OF_ROWS}`,
    'type=json'
  ].join('&');

  return `${API_BASE}?${qs}`;
}

function asNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  const s = String(value ?? '').trim();
  if (!s) {
    return null;
  }
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

function asInt(value) {
  const n = asNumber(value);
  if (n == null) {
    return null;
  }
  const i = Math.trunc(n);
  return Number.isFinite(i) ? i : null;
}

function extractItemsAndTotalCount(json) {
  // Typical data.go.kr "openapi" envelope:
  // { response: { header: {...}, body: { items: { item: [...] }, totalCount: ... } } }
  const body = json?.response?.body;
  if (body) {
    const totalCount = asInt(body.totalCount) ?? asInt(body.matchCount) ?? asInt(body.total_count);
    const itemsNode = body.items?.item ?? body.items ?? [];
    const items = Array.isArray(itemsNode) ? itemsNode : itemsNode ? [itemsNode] : [];
    return { items, totalCount: totalCount ?? items.length };
  }

  // Fallback: odcloud style { data: [...], totalCount: ... }
  if (Array.isArray(json?.data)) {
    const totalCount = asInt(json.totalCount) ?? json.data.length;
    return { items: json.data, totalCount };
  }

  throw new Error('Unexpected API response shape.');
}

function normalizeItem(item) {
  const lat = asNumber(item?.latitude);
  const lon = asNumber(item?.longitude);
  if (lat == null || lon == null) {
    return null;
  }

  const idRaw = String(item?.mnlssRegltCameraManageNo || '').trim();
  const id = idRaw || `${lat.toFixed(6)},${lon.toFixed(6)}`;
  const limit = asInt(item?.lmttVe);

  return {
    id,
    lat,
    lon,
    // Null means "unknown/not provided".
    limitKph: limit != null && limit > 0 ? limit : null
  };
}

async function main() {
  const start = Date.now();
  let pageNo = 1;
  let totalCount = null;
  const seen = new Set();
  const cameras = [];

  while (true) {
    const url = buildURL(pageNo);
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new Error(`HTTP ${res.status} fetching page=${pageNo}: ${text.slice(0, 240)}`);
    }

    const json = await res.json();
    const extracted = extractItemsAndTotalCount(json);
    if (totalCount == null) {
      totalCount = extracted.totalCount;
      console.log(`totalCount=${totalCount} numOfRows=${NUM_OF_ROWS}`);
    }

    for (const raw of extracted.items) {
      const normalized = normalizeItem(raw);
      if (!normalized) {
        continue;
      }
      if (seen.has(normalized.id)) {
        continue;
      }
      seen.add(normalized.id);
      cameras.push(normalized);
    }

    const fetchedSoFar = pageNo * NUM_OF_ROWS;
    console.log(`page=${pageNo} items=${extracted.items.length} cameras=${cameras.length}`);

    if (extracted.items.length === 0) {
      break;
    }
    if (totalCount != null && fetchedSoFar >= totalCount) {
      break;
    }
    pageNo += 1;
    if (pageNo > 2000) {
      throw new Error('Safety stop: too many pages. Check API parameters.');
    }
  }

  cameras.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const payload = {
    schemaVersion: 1,
    source: 'data.go.kr: tn_pubr_public_unmanned_traffic_camera_api',
    updatedAt: new Date().toISOString(),
    count: cameras.length,
    cameras
  };

  await fs.mkdir(path.dirname(OUT_PATH), { recursive: true });
  await fs.writeFile(OUT_PATH, JSON.stringify(payload), 'utf8');

  const seconds = ((Date.now() - start) / 1000).toFixed(1);
  console.log(`wrote ${OUT_PATH} (${cameras.length} cameras) in ${seconds}s`);
}

main().catch((err) => {
  console.error(err?.stack || String(err));
  process.exit(1);
});
