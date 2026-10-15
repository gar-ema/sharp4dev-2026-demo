#!/usr/bin/env bash
# Mostra choose/when + Random: /catalog/products?chaos=true fallisce ~50% delle volte con 503 (e Retry-After).
source "$(dirname "$0")/env.sh"; ENV="${1:-dev}"; GW="https://${PREFIX}-${ENV}.azure-api.net"
for i in $(seq 1 10); do printf "%s " "$(curl -s -o /dev/null -w '%{http_code}' "$GW/catalog/products?chaos=true")"; done; echo
