#!/bin/bash
set -euo pipefail

# build script for Docker builder stage
# Assure d'être dans /src
cd /src || exit 1

echo "Builder script: detecting project type..."

# Force create dist target
mkdir -p /src/dist

# helper to copy with rsync and exclude builder/dist
copy_to_dist() {
  SRC="$1"
  echo "Copying from '$SRC' -> /src/dist (rsync excludes .git, builder, dist, node_modules)"
  # use rsync to avoid copying .git, builder, dist itself, etc.
  rsync -a --delete \
    --exclude='.git' \
    --exclude='builder' \
    --exclude='dist' \
    --exclude='node_modules' \
    --exclude='venv' \
    --exclude='__pycache__' \
    "$SRC"/ /src/dist/
}

# Node.js project?
if [ -f package.json ]; then
  echo "Detected Node.js project (package.json present)."
  # try to build if scripts exist
  if command -v npm >/dev/null 2>&1; then
    npm install --no-audit --no-fund || true
    npm run build --if-present || true
  else
    echo "npm not found in builder image; skipping npm install/build"
  fi
  # common build outputs: dist or build
  if [ -d dist ]; then
    copy_to_dist "dist"
  elif [ -d build ]; then
    copy_to_dist "build"
  else
    # if nothing built, copy src files (static fallback)
    copy_to_dist "."
  fi
  exit 0
fi

# Python project?
if ls *.py >/dev/null 2>&1; then
  echo "Detected Python files -> treat as Python web app (copy all)."
  # Optionally create virtualenv / install deps - not required in static builder
  copy_to_dist "."
  exit 0
fi

# default: static site
echo "No package.json and no Python files detected — treat as static site."
copy_to_dist "."
exit 0

