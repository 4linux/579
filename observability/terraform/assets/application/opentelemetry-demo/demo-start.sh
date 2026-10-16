#!/usr/bin/env bash
set -euo pipefail
cd /opt/application/opentelemetry-demo/upstream
cp -f ../compose.yaml ./compose.yaml
# O Compose principal e o perfil minimo oficial; nao inicia Grafana/Jaeger duplicados.
docker compose -f compose.yaml -f compose.yaml up -d --pull always
printf '\nLoja: http://IP_PUBLICO_APPLICATION:8080\n'
