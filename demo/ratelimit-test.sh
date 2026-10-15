#!/usr/bin/env bash
# Mostra il rate limit: 8 chiamate in sequenza, conta i 429. Uso: ./demo/ratelimit-test.sh dev|qa|prod
source "$(dirname "$0")/env.sh"; ENV="${1:-dev}"; N="${PREFIX}-${ENV}"
for i in $(seq 1 8); do printf "%s " "$(curl -s -o /dev/null -w '%{http_code}' "https://${N}.azure-api.net/orders")"; done; echo
