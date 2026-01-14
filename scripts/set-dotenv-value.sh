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

shell_quote_single() {
  # Single-quote a value so it can be safely sourced from .env.
  # Handles values containing spaces, &, ?, =, etc.
  local s="$1"
  s=${s//\'/\'"\'"\'}  # ' -> '"'"'
  printf "'%s'" "$s"
}

quoted_value="$(shell_quote_single "$value")"

replacement_line="${key}=${quoted_value}"

# Escape sed replacement chars
escaped_replacement_line="${replacement_line//\\/\\\\}"
escaped_replacement_line="${escaped_replacement_line//&/\\&}"
escaped_replacement_line="${escaped_replacement_line//|/\\|}"

tmp_file="${env_file}.tmp"

if grep -qE "^${key}=" "$env_file"; then
  sed -E "s|^${key}=.*|${escaped_replacement_line}|" "$env_file" > "$tmp_file"
else
  cat "$env_file" > "$tmp_file"
  printf "\n%s=%s\n" "$key" "$quoted_value" >> "$tmp_file"
fi

mv "$tmp_file" "$env_file"

echo "Set $key in .env"
