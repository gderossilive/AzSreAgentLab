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

if [[ -d "external/sre-agent-lab" ]]; then
  echo "external/sre-agent-lab already exists; skipping clone"
else
  git clone https://github.com/dm-chelupati/sre-agent-lab.git external/sre-agent-lab
fi
