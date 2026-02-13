#!/usr/bin/env node
/**
 * Build Korea unmanned traffic camera dataset by downloading fileData CSVs from data.go.kr,
 * then write a compact JSON file compatible with backend/server.mjs at /api/data/speed_cameras_kr.
 *
 * Why this exists:
 * - Sometimes the official OpenAPI returns resultCode=30 (SERVICE KEY IS NOT REGISTERED).
 * - fileData downloads usually work without an OpenAPI serviceKey and can be aggregated.
 *
 * Usage (inside backend container or on host):
 *   node backend/scripts/update_speed_cameras_kr_from_filedata.mjs
 *
 * Env:
 *   DATA_GO_KR_STD_DATA_ID=15028200   # "전국무인교통단속카메라표준데이터"
 *   OUT_PATH=./data/speed_cameras_kr.min.json
 *   DOWNLOAD_DIR=./data/raw/speed_cameras_kr
 *   MAX_DATASETS=0                   # 0 = no limit (default)
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, '..');

const BASE = String(process.env.DATA_GO_KR_BASE || '').trim() || 'https://www.data.go.kr';
const STD_ID = String(process.env.DATA_GO_KR_STD_DATA_ID || '15028200').trim();
const MAX_DATASETS = Math.max(0, Number(process.env.MAX_DATASETS || 0));
const OUT_PATH =
  String(process.env.OUT_PATH || '').trim() ||
  path.resolve(ROOT, 'data/speed_cameras_kr.min.json');
const DOWNLOAD_DIR =
  String(process.env.DOWNLOAD_DIR || '').trim() ||
  path.resolve(ROOT, 'data/raw/speed_cameras_kr');

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchText(url) {
  const res = await fetch(url, {
    redirect: 'follow',
    headers: {
      Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'User-Agent': 'tesla-info/1.0 (speed-cameras-filedata)'
    }
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`HTTP ${res.status} fetching ${url}: ${body.slice(0, 240)}`);
  }
  return await res.text();
}

async function fetchJson(url) {
  const res = await fetch(url, {
    redirect: 'follow',
    headers: {
      Accept: 'application/json,text/plain,*/*',
      'User-Agent': 'tesla-info/1.0 (speed-cameras-filedata)'
    }
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} fetching ${url}: ${text.slice(0, 240)}`);
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`Non-JSON response fetching ${url}: ${text.slice(0, 240)}`);
  }
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

function parseCsvRows(text) {
  // Minimal RFC4180-ish parser (supports quotes and escaped quotes).
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;

  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];

    if (inQuotes) {
      if (ch === '"') {
        const next = text[i + 1];
        if (next === '"') {
          field += '"';
          i += 1;
          continue;
        }
        inQuotes = false;
        continue;
      }
      field += ch;
      continue;
    }

    if (ch === '"') {
      inQuotes = true;
      continue;
    }
    if (ch === ',') {
      row.push(field);
      field = '';
      continue;
    }
    if (ch === '\n') {
      row.push(field);
      field = '';
      // Trim trailing \r.
      if (row.length && typeof row[row.length - 1] === 'string') {
        row[row.length - 1] = row[row.length - 1].replace(/\r$/, '');
      }
      rows.push(row);
      row = [];
      continue;
    }
    field += ch;
  }

  if (field.length || row.length) {
    row.push(field.replace(/\r$/, ''));
    rows.push(row);
  }

  return rows;
}

function decodeUtf8(bytes) {
  // Strip UTF-8 BOM if present.
  let view = bytes;
  if (view.length >= 3 && view[0] === 0xef && view[1] === 0xbb && view[2] === 0xbf) {
    view = view.subarray(3);
  }
  return new TextDecoder('utf-8', { fatal: false }).decode(view);
}

function safeFilename(name) {
  return String(name || '')
    .trim()
    .replace(/[\\/:*?"<>|]/g, '_')
    .replace(/\s+/g, '_')
    .slice(0, 240);
}

function parseContentDispositionFilename(headerValue) {
  const value = String(headerValue || '');
  // Support both filename= and filename*=UTF-8''.
  const star = value.match(/filename\*\s*=\s*UTF-8''([^;]+)/i);
  if (star && star[1]) {
    try {
      return decodeURIComponent(star[1].trim());
    } catch {
      return star[1].trim();
    }
  }
  const plain = value.match(/filename\s*=\s*\"?([^\";]+)\"?/i);
  return plain && plain[1] ? plain[1].trim() : null;
}

function extractFileDataIds(html, stdId) {
  const ids = new Set();
  const candidates = [];

  // Common pattern: /data/<id>/fileData.do
  for (const match of html.matchAll(/\/data\/(\d{6,})\/fileData\.do/gi)) {
    candidates.push(match[1]);
  }

  // Less common pattern: fileData.do?dataId=<id>
  for (const match of html.matchAll(/fileData\.do\?[^\"']*?\bdataId=(\d{6,})/gi)) {
    candidates.push(match[1]);
  }

  for (const id of candidates) {
    if (!id) {
      continue;
    }
    ids.add(id);
  }

  // Sometimes the page doesn't embed all ids; ensure stdId is included to at least fetch one dataset.
  if (stdId) {
    ids.add(stdId);
  }

  return Array.from(ids);
}

function extractUddi(html) {
  const match = html.match(/uddi:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/);
  return match ? match[0] : null;
}

function findFirstKeyValue(obj, key) {
  const seen = new Set();
  const queue = [obj];

  while (queue.length) {
    const current = queue.shift();
    if (!current || typeof current !== 'object') {
      continue;
    }
    if (seen.has(current)) {
      continue;
    }
    seen.add(current);

    if (Object.prototype.hasOwnProperty.call(current, key)) {
      const value = current[key];
      if (value != null && String(value).trim() !== '') {
        return value;
      }
    }

    for (const value of Object.values(current)) {
      if (value && typeof value === 'object') {
        queue.push(value);
      }
    }
  }

  return null;
}

async function downloadFile({ dataId, uddi, destDir }) {
  const metaUrl = `${BASE}/tcs/dss/selectFileDataDownload.do?publicDataPk=${encodeURIComponent(
    dataId
  )}&publicDataDetailPk=${encodeURIComponent(uddi)}`;
  const meta = await fetchJson(metaUrl);

  const atchFileId = findFirstKeyValue(meta, 'atchFileId');
  const fileDetailSn = findFirstKeyValue(meta, 'fileDetailSn') ?? '1';

  if (!atchFileId) {
    const preview = JSON.stringify(meta).slice(0, 240);
    throw new Error(`Missing atchFileId in meta for dataId=${dataId}: ${preview}`);
  }

  const downloadUrl = `${BASE}/dataset/fileDownload.do?atchFileId=${encodeURIComponent(
    atchFileId
  )}&fileDetailSn=${encodeURIComponent(fileDetailSn)}&publicDataDetailPk=${encodeURIComponent(uddi)}`;

  const res = await fetch(downloadUrl, {
    redirect: 'follow',
    headers: { 'User-Agent': 'tesla-info/1.0 (speed-cameras-filedata)' }
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`HTTP ${res.status} downloading dataId=${dataId}: ${body.slice(0, 240)}`);
  }

  const cd = res.headers.get('content-disposition');
  const filenameRaw = parseContentDispositionFilename(cd) || `data_${dataId}.csv`;
  const filename = safeFilename(filenameRaw);
  const filePath = path.resolve(destDir, filename);

  const bytes = new Uint8Array(await res.arrayBuffer());
  await fs.mkdir(destDir, { recursive: true });
  await fs.writeFile(filePath, bytes);

  return { filePath, filename, bytes };
}

function parseCamerasFromCsvBytes(bytes) {
  const text = decodeUtf8(bytes);
  const rows = parseCsvRows(text);
  if (!rows.length) {
    return [];
  }

  const header = rows[0].map((v) => String(v || '').trim());
  const idx = (keys) => {
    for (const key of keys) {
      const i = header.findIndex((h) => h === key);
      if (i >= 0) {
        return i;
      }
    }
    return -1;
  };

  const manageIdx = idx(['mnlssRegltCameraManageNo', '관리번호']);
  const latIdx = idx(['latitude', '위도', 'lat']);
  const lonIdx = idx(['longitude', '경도', 'lon', 'lng']);
  const limitIdx = idx(['lmttVe', '제한속도']);

  if (latIdx < 0 || lonIdx < 0) {
    return [];
  }

  const cameras = [];
  for (let r = 1; r < rows.length; r += 1) {
    const row = rows[r];
    if (!row || !row.length) {
      continue;
    }

    const lat = asNumber(row[latIdx]);
    const lon = asNumber(row[lonIdx]);
    if (lat == null || lon == null) {
      continue;
    }

    const manageNo = manageIdx >= 0 ? String(row[manageIdx] || '').trim() : '';
    const id = manageNo || `${lat.toFixed(6)},${lon.toFixed(6)}`;
    const limit = limitIdx >= 0 ? asInt(row[limitIdx]) : null;

    cameras.push({
      id,
      lat,
      lon,
      limitKph: limit != null && limit > 0 ? limit : null
    });
  }

  return cameras;
}

async function main() {
  const startedAt = Date.now();

  const stdUrl = `${BASE}/tcs/dss/selectStdDataDetailView.do?publicDataPk=${encodeURIComponent(STD_ID)}`;
  console.log(`Fetching std page: ${stdUrl}`);
  const stdHtml = await fetchText(stdUrl);
  const ids = extractFileDataIds(stdHtml, STD_ID);

  console.log(`Found ${ids.length} candidate fileData ids (std=${STD_ID}).`);
  const selectedIds = MAX_DATASETS > 0 ? ids.slice(0, MAX_DATASETS) : ids;

  const seen = new Set();
  const all = [];
  let okDatasets = 0;

  for (let i = 0; i < selectedIds.length; i += 1) {
    const dataId = selectedIds[i];
    const detailUrl = `${BASE}/data/${encodeURIComponent(dataId)}/fileData.do`;
    console.log(`[${i + 1}/${selectedIds.length}] detail=${detailUrl}`);

    let detailHtml = '';
    try {
      detailHtml = await fetchText(detailUrl);
    } catch (error) {
      console.warn(`  skip dataId=${dataId} (detail fetch failed): ${error instanceof Error ? error.message : error}`);
      continue;
    }

    const uddi = extractUddi(detailHtml);
    if (!uddi) {
      console.warn(`  skip dataId=${dataId} (uddi not found)`);
      continue;
    }

    // Cache download to avoid repeated network work.
    const cacheKey = safeFilename(`${dataId}_${uddi}.csv`);
    const cachePath = path.resolve(DOWNLOAD_DIR, cacheKey);

    let bytes = null;
    try {
      bytes = await fs.readFile(cachePath);
      console.log(`  cache hit: ${cacheKey}`);
    } catch {
      // ignore
    }

    if (!bytes) {
      try {
        const downloaded = await downloadFile({ dataId, uddi, destDir: DOWNLOAD_DIR });
        // Also write a stable cache path for future runs.
        await fs.writeFile(cachePath, downloaded.bytes);
        bytes = downloaded.bytes;
        console.log(`  downloaded: ${downloaded.filename}`);
        // Be polite to the portal.
        await sleep(250);
      } catch (error) {
        console.warn(`  skip dataId=${dataId} (download failed): ${error instanceof Error ? error.message : error}`);
        continue;
      }
    }

    const cameras = parseCamerasFromCsvBytes(bytes);
    if (!cameras.length) {
      console.warn(`  parsed 0 cameras from dataId=${dataId} (unexpected schema?)`);
      continue;
    }

    okDatasets += 1;
    for (const cam of cameras) {
      if (seen.has(cam.id)) {
        continue;
      }
      seen.add(cam.id);
      all.push(cam);
    }

    console.log(`  +${cameras.length} rows, total unique=${all.length}`);
  }

  all.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  const payload = {
    schemaVersion: 1,
    source: `data.go.kr fileData aggregation (std=${STD_ID})`,
    updatedAt: new Date().toISOString(),
    datasetsFetched: okDatasets,
    count: all.length,
    cameras: all
  };

  await fs.mkdir(path.dirname(OUT_PATH), { recursive: true });
  await fs.writeFile(OUT_PATH, JSON.stringify(payload), 'utf8');

  const seconds = ((Date.now() - startedAt) / 1000).toFixed(1);
  console.log(`wrote ${OUT_PATH} (${all.length} cameras; datasets=${okDatasets}) in ${seconds}s`);
}

main().catch((err) => {
  console.error(err?.stack || String(err));
  process.exit(1);
});

