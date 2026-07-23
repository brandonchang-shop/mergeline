#!/bin/bash
# Pull latest, rebuild, and restart Mergeline.
set -e
cd "$(dirname "$0")"

echo "Pulling latest…"
git pull --ff-only

./build.sh

echo "Restarting…"
pkill -x Mergeline 2>/dev/null || true
sleep 1
open build/Mergeline.app
echo "✅ Mergeline restarted"
