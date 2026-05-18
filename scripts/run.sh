#!/bin/bash
# Build the app bundle and launch it.
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build-app.sh
open "build/JT's Ping Monitor.app"
