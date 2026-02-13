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

function extractFileDataDetailPks(html) {
  // On the standard dataset detail page, file datasets are listed as:
  //   onclick="stdObj.fn_fileDataDetail('uddi:...')"
  // The value passed is the "publicDataDetailPk" used by selectFileDataDownload.do.
  const matches = html.matchAll(/stdObj\.fn_fileDataDetail\('([^']+)'\)/g);
  const result = [];
  const seen = new Set();

  for (const match of matches) {
    const pk = String(match?.[1] || '').trim();
    if (!pk) {
      continue;
    }
    if (seen.has(pk)) {
      continue;
    }
    seen.add(pk);
    result.push(pk);
  }

  return result;
}

function extractMaxPageIndex(html) {
  // Pagination links look like: onclick="stdObj.fn_pageClick(26); return false;"
  let max = 1;
  for (const match of html.matchAll(/stdObj\.fn_pageClick\((\d+)\)/g)) {
    const n = Number(match?.[1]);
    if (Number.isFinite(n) && n > max) {
      max = n;
    }
  }
  return max;
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

async function downloadFileByAtchId({ atchFileId, fileDetailSn, dataNm, outPath }) {
  // The portal uses /cmm/cmm/fileDownload.do (see fn_fileDownload/fn_fileDataDownload in script_cmmFunction.js).
  const downloadUrl = `${BASE}/cmm/cmm/fileDownload.do?atchFileId=${encodeURIComponent(
    atchFileId
  )}&fileDetailSn=${encodeURIComponent(fileDetailSn)}&dataNm=${encodeURIComponent(String(dataNm))}`;

  const res = await fetch(downloadUrl, {
    redirect: 'follow',
    headers: { 'User-Agent': 'tesla-info/1.0 (speed-cameras-filedata)' }
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(
      `HTTP ${res.status} downloading atchFileId=${atchFileId} sn=${fileDetailSn}: ${body.slice(0, 240)}`
    );
  }

  const bytes = new Uint8Array(await res.arrayBuffer());
  await fs.mkdir(path.dirname(outPath), { recursive: true });
  await fs.writeFile(outPath, bytes);
  return { bytes };
}

function parseCamerasFromCsvBytes(bytes) {
  const view =
    bytes && bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf
      ? bytes.subarray(3)
      : bytes;

  const decode = (encoding) => new TextDecoder(encoding, { fatal: false }).decode(view);

  const parseWithText = (text) => {
    const rows = parseCsvRows(text);
    if (!rows.length) {
      return { cameras: [], header: [] };
    }

    const header = rows[0].map((v) => String(v || '').trim());
    const idx = (exactKeys, containsKeys = []) => {
      for (const key of exactKeys) {
        const i = header.findIndex((h) => h === key);
        if (i >= 0) {
          return i;
        }
      }
      for (const key of containsKeys) {
        const i = header.findIndex((h) => String(h || '').includes(key));
        if (i >= 0) {
          return i;
        }
      }
      return -1;
    };

    // manageNo is not globally unique across municipalities, so we do not use it as the primary id.
    const latIdx = idx(['latitude', '위도', 'lat'], ['위도']);
    const lonIdx = idx(['longitude', '경도', 'lon', 'lng'], ['경도']);
    const limitIdx = idx(['lmttVe', '제한속도'], ['제한속도']);

    if (latIdx < 0 || lonIdx < 0) {
      return { cameras: [], header };
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

      const id = `${lat.toFixed(6)},${lon.toFixed(6)}`;
      const limit = limitIdx >= 0 ? asInt(row[limitIdx]) : null;

      cameras.push({
        id,
        lat,
        lon,
        limitKph: limit != null && limit > 0 ? limit : null
      });
    }

    return { cameras, header };
  };

  // Most fileData CSVs are UTF-8 with BOM, but some datasets are EUC-KR/CP949.
  // Try UTF-8 first, then fallback to EUC-KR if we can't find lat/lon columns.
  const utf8 = parseWithText(decode('utf-8'));
  if (utf8.cameras.length) {
    return utf8.cameras;
  }
  const euckr = parseWithText(decode('euc-kr'));
  return euckr.cameras;
}

async function main() {
  const startedAt = Date.now();

  const stdUrl = `${BASE}/tcs/dss/selectStdDataDetailView.do?publicDataPk=${encodeURIComponent(STD_ID)}`;
  console.log(`Fetching std page: ${stdUrl}`);
  const stdHtml = await fetchText(stdUrl);

  // Some environments (or portal variants) omit pagination links on page 1.
  // In that case we'll probe subsequent pages until we stop finding entries.
  const maxPage = extractMaxPageIndex(stdHtml);
  const pkSeen = new Set();
  const detailPks = [];

  const targetCount = MAX_DATASETS > 0 ? MAX_DATASETS : Number.POSITIVE_INFINITY;
  const addPks = (pks) => {
    for (const pk of pks) {
      if (pkSeen.has(pk)) {
        continue;
      }
      pkSeen.add(pk);
      detailPks.push(pk);
      if (detailPks.length >= targetCount) {
        return true;
      }
    }
    return false;
  };

  // Page 1 is embedded in the std detail view itself.
  addPks(extractFileDataDetailPks(stdHtml));

  // Remaining pages are loaded via AJAX; fetch them directly.
  let pagesFetched = 1;
  if (detailPks.length < targetCount) {
    if (maxPage <= 1) {
      const maxProbePages = 40;
      let emptyStreak = 0;

      for (let pageIndex = 2; pageIndex <= maxProbePages; pageIndex += 1) {
        const pageUrl = `${BASE}/tcs/dss/stdFileList.do?publicDataPk=${encodeURIComponent(
          STD_ID
        )}&pageIndex=${encodeURIComponent(pageIndex)}`;
        const pageHtml = await fetchText(pageUrl);
        pagesFetched = pageIndex;

        const before = detailPks.length;
        if (addPks(extractFileDataDetailPks(pageHtml))) {
          break;
        }
        const added = detailPks.length - before;
        if (added <= 0) {
          emptyStreak += 1;
          if (emptyStreak >= 2) {
            break;
          }
        } else {
          emptyStreak = 0;
        }
        // Be polite to the portal.
        await sleep(120);
      }
    } else {
      for (let pageIndex = 2; pageIndex <= maxPage; pageIndex += 1) {
        const pageUrl = `${BASE}/tcs/dss/stdFileList.do?publicDataPk=${encodeURIComponent(
          STD_ID
        )}&pageIndex=${encodeURIComponent(pageIndex)}`;
        const pageHtml = await fetchText(pageUrl);
        pagesFetched = pageIndex;

        if (addPks(extractFileDataDetailPks(pageHtml))) {
          break;
        }
        // Be polite to the portal.
        await sleep(120);
      }
    }
  }

  const pageInfo = maxPage > 1 ? `pages=${maxPage}` : 'pages=unknown';
  console.log(
    `Found ${detailPks.length} fileData entries (std=${STD_ID}; ${pageInfo}; pagesFetched=${pagesFetched}).`
  );
  const selectedDetailPks = MAX_DATASETS > 0 ? detailPks.slice(0, MAX_DATASETS) : detailPks;

  const byCoord = new Map();
  let okDatasets = 0;

  for (let i = 0; i < selectedDetailPks.length; i += 1) {
    const publicDataDetailPk = selectedDetailPks[i];
    console.log(`[${i + 1}/${selectedDetailPks.length}] pk=${publicDataDetailPk}`);

    // We need meta to resolve atchFileId/fileDetailSn and also to know a stable-ish dataset name.
    // If the raw CSV exists, we still parse it; but meta is cheap and helps logging.
    let meta = null;
    try {
      const metaUrl = `${BASE}/tcs/dss/selectFileDataDownload.do?recommendDataYn=Y&publicDataPk=${encodeURIComponent(
        STD_ID
      )}&publicDataDetailPk=${encodeURIComponent(publicDataDetailPk)}`;
      meta = await fetchJson(metaUrl);
    } catch (error) {
      console.warn(`  skip pk=${publicDataDetailPk} (meta fetch failed): ${error instanceof Error ? error.message : error}`);
      continue;
    }

    const ok = meta?.status === true || meta?.status === 'true';
    if (!ok) {
      const reason = String(meta?.errorDc || meta?.message || '').trim();
      console.warn(`  skip pk=${publicDataDetailPk} (meta status=false)${reason ? `: ${reason}` : ''}`);
      continue;
    }

    const dataNm = findFirstKeyValue(meta, 'dataNm') || findFirstKeyValue(meta, 'dataSetNm') || 'speed_cameras_kr';
    const atchFileId = findFirstKeyValue(meta, 'atchFileId');
    const fileDetailSn = findFirstKeyValue(meta, 'fileDetailSn') ?? '1';

    if (!atchFileId) {
      console.warn(`  skip pk=${publicDataDetailPk} (missing atchFileId)`);
      continue;
    }

    // Cache by atchFileId + fileDetailSn (more stable than detailPk suffixes).
    const cacheKey = safeFilename(`${String(dataNm).trim() || 'speed_cameras'}_${atchFileId}_${fileDetailSn}.csv`);
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
        const downloaded = await downloadFileByAtchId({
          atchFileId,
          fileDetailSn,
          dataNm,
          outPath: cachePath
        });
        bytes = downloaded.bytes;

        console.log(`  downloaded -> ${cacheKey}`);
        // Be polite to the portal.
        await sleep(250);
      } catch (error) {
        console.warn(`  skip pk=${publicDataDetailPk} (download failed): ${error instanceof Error ? error.message : error}`);
        continue;
      }
    }

    const cameras = parseCamerasFromCsvBytes(bytes);
    if (!cameras.length) {
      console.warn(`  parsed 0 cameras from pk=${publicDataDetailPk} (unexpected schema/encoding?)`);
      continue;
    }

    okDatasets += 1;
    for (const cam of cameras) {
      const existing = byCoord.get(cam.id);
      if (!existing) {
        byCoord.set(cam.id, cam);
        continue;
      }

      // Prefer a known speed limit; if conflicting, keep the smaller (more conservative) limit.
      if (existing.limitKph == null && cam.limitKph != null) {
        existing.limitKph = cam.limitKph;
      } else if (existing.limitKph != null && cam.limitKph != null && existing.limitKph !== cam.limitKph) {
        existing.limitKph = Math.min(existing.limitKph, cam.limitKph);
      }
    }

    console.log(`  +${cameras.length} rows, total unique=${byCoord.size}`);
  }

  const all = Array.from(byCoord.values());
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
