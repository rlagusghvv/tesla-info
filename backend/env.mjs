import fs from 'node:fs';

export function loadEnvFile(filePath) {
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

export function upsertEnvFile(filePath, pairs, { mode = 0o600 } = {}) {
  let txt = '';
  if (fs.existsSync(filePath)) {
    txt = fs.readFileSync(filePath, 'utf8');
  }

  for (const [key, value] of Object.entries(pairs)) {
    const safeValue = value === null || value === undefined ? '' : String(value);
    const re = new RegExp(`^${escapeRegex(key)}=.*$`, 'm');
    if (re.test(txt)) {
      txt = txt.replace(re, `${key}=${safeValue}`);
    } else {
      txt += (txt.endsWith('\n') ? '' : '\n') + `${key}=${safeValue}\n`;
    }
  }

  fs.writeFileSync(filePath, txt, { mode });
}

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
