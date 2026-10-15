#!/usr/bin/env bash
# Mostra llm-token-limit: prompt lunghi in sequenza finché il gateway risponde 429. Uso: ./demo/genai-tokenlimit-test.sh [dev]
source "$(dirname "$0")/env.sh"; ENV="${1:-dev}"; GW="https://${PREFIX}-${ENV}.azure-api.net"
LONG=$(python3 -c "print('Spiegami APIOps in dettaglio. ' * 6)")
for i in $(seq 1 8); do
  printf "%s: " "$i"
  curl -s -o /dev/null -w '%{http_code}  remaining=%header{x-ratelimit-remaining-tokens}\n' -X POST "$GW/genai/chat/completions" \
    -H 'Content-Type: application/json' -d "{\"model\":\"mock\",\"messages\":[{\"role\":\"user\",\"content\":\"$LONG\"}]}"
done
