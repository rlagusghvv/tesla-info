#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
EXAMPLE_FILE="$ROOT_DIR/backend/.env.example"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$EXAMPLE_FILE" "$ENV_FILE"
  echo "Created $ENV_FILE from template."
fi

set_kv() {
  local key="$1"
  local value="$2"
  local file="$3"

  awk -v key="$key" -v value="$value" '
    BEGIN { found = 0 }
    $0 ~ "^" key "=" {
      print key "=" value
      found = 1
      next
    }
    { print }
    END {
      if (!found) {
        print key "=" value
      }
    }
  ' "$file" > "$file.tmp"

  mv "$file.tmp" "$file"
}

read -r -p "TESLA_CLIENT_ID (required): " tesla_client_id
if [[ -z "$tesla_client_id" ]]; then
  echo "TESLA_CLIENT_ID is required." >&2
  exit 1
fi

read -r -p "TESLA_CLIENT_SECRET (required): " tesla_client_secret
if [[ -z "$tesla_client_secret" ]]; then
  echo "TESLA_CLIENT_SECRET is required." >&2
  exit 1
fi

read -r -p "TESLA_REDIRECT_URI (required, https://.../oauth/callback): " tesla_redirect_uri
if [[ -z "$tesla_redirect_uri" ]]; then
  echo "TESLA_REDIRECT_URI is required." >&2
  exit 1
fi

read -r -p "TESLA_DOMAIN (required, example: tesla-subdash.example.com): " tesla_domain
if [[ -z "$tesla_domain" ]]; then
  echo "TESLA_DOMAIN is required." >&2
  exit 1
fi

read -r -p "TESLA_VIN (optional, Enter to auto-select first vehicle): " tesla_vin
read -r -p "POLL_INTERVAL_MS [8000]: " poll_interval
if [[ -z "$poll_interval" ]]; then
  poll_interval="8000"
fi

set_kv "USE_SIMULATOR" "0" "$ENV_FILE"
set_kv "POLL_TESLA" "1" "$ENV_FILE"
set_kv "POLL_INTERVAL_MS" "$poll_interval" "$ENV_FILE"
set_kv "TESLA_CLIENT_ID" "$tesla_client_id" "$ENV_FILE"
set_kv "TESLA_CLIENT_SECRET" "$tesla_client_secret" "$ENV_FILE"
set_kv "TESLA_REDIRECT_URI" "$tesla_redirect_uri" "$ENV_FILE"
set_kv "TESLA_DOMAIN" "$tesla_domain" "$ENV_FILE"
set_kv "TESLA_VIN" "$tesla_vin" "$ENV_FILE"

chmod 600 "$ENV_FILE"

echo "Saved Tesla settings to $ENV_FILE"
echo "Next:"
echo "  1) npm run tesla:partner:register"
echo "  2) npm run tesla:oauth:start"
echo "  3) npm run tesla:oauth:exchange -- <code>"
echo "  4) npm run backend:start:tesla"
