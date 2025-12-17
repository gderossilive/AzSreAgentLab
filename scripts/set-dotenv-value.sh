#!/usr/bin/env bash
set -euo pipefail

# Update or insert KEY=VALUE into the root .env file.
# Usage:
#   scripts/set-dotenv-value.sh KEY VALUE

key="${1:?Missing key}"
value="${2-}"

env_file="${PWD}/.env"
if [[ ! -f "$env_file" ]]; then
  echo "ERROR: $env_file not found" >&2
  exit 1
fi

# Escape sed replacement chars
escaped_value="${value//\\/\\\\}"
escaped_value="${escaped_value//&/\\&}"

tmp_file="${env_file}.tmp"

if grep -qE "^${key}=" "$env_file"; then
  sed -E "s|^(${key}=).*|\\1${escaped_value}|" "$env_file" > "$tmp_file"
else
  cat "$env_file" > "$tmp_file"
  printf "\n%s=%s\n" "$key" "$value" >> "$tmp_file"
fi

mv "$tmp_file" "$env_file"

echo "Set $key in .env"
