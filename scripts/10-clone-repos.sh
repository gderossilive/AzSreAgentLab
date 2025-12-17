#!/usr/bin/env bash
set -euo pipefail

mkdir -p external

if [[ ! -d "external/sre-agent/.git" ]]; then
  git clone https://github.com/microsoft/sre-agent.git external/sre-agent
else
  echo "external/sre-agent already exists; skipping clone"
fi

if [[ ! -d "external/octopets/.git" ]]; then
  git clone https://github.com/Azure-Samples/octopets.git external/octopets
else
  echo "external/octopets already exists; skipping clone"
fi
