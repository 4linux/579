#!/usr/bin/env bash
set -euo pipefail
cd /opt/application/opentelemetry-demo/upstream
docker compose -f compose.yaml -f compose.yaml down
