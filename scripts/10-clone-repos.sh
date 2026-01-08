#!/usr/bin/env bash
set -euo pipefail

mkdir -p external

if [[ -d "external/sre-agent" ]]; then
  echo "external/sre-agent already exists; skipping clone"
else
  git clone https://github.com/microsoft/sre-agent.git external/sre-agent
fi

if [[ -d "external/octopets" ]]; then
  echo "external/octopets already exists; skipping clone"
else
  git clone https://github.com/Azure-Samples/octopets.git external/octopets
fi
