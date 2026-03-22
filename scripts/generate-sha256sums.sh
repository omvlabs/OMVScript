#!/usr/bin/env bash
set -euo pipefail
# Generate sha256 sums for key scripts (for releases)
FILES=(
  install.sh
  modules/docker-check.sh
  modules/developer/install-dev-env.sh
)

for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then
    sha256sum "$f"
  fi
done
