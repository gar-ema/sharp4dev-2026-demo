#!/usr/bin/env bash
# Chiama le tre API sui tre ambienti e mostra gli header utili. Uso: ./demo/smoke.sh [dev|qa|prod|all]
source "$(dirname "$0")/env.sh"; SEL="${1:-all}"
for ENV in dev qa prod; do
  [ "$SEL" = all ] || [ "$SEL" = "$ENV" ] || continue
  N="${PREFIX}-${ENV}"; GW="https://${N}.azure-api.net"; echo "===== ${ENV}  ${GW}"
  echo "-- GET /orders"; curl -s -i "$GW/orders" | grep -iE '^(HTTP|X-Environment|X-Api-Version)'
  echo "-- GET /catalog/products (2 volte: seconda con X-Cache: HIT e stesso X-Generated-At)"
  for i in 1 2; do curl -s -i "$GW/catalog/products" | grep -iE '^(HTTP|X-Cache|X-Generated-At|X-Environment)'; done
  echo "-- GET /catalog/products/P100/price senza header → 401, con header → 200"
  curl -s -o /dev/null -w '%{http_code} ' "$GW/catalog/products/P100/price"; curl -s -w ' %{http_code}\n' -H 'X-Client-Id: sharp4dev' "$GW/catalog/products/P100/price"
  echo "-- POST /genai/chat/completions"
  curl -s -i -X POST "$GW/genai/chat/completions" -H 'Content-Type: application/json' \
    -d '{"model":"mock","messages":[{"role":"user","content":"Cos è APIOps?"}]}' | grep -iE '^(HTTP|X-Environment|x-ratelimit-remaining-tokens|x-tokens-consumed)|"content"'
done
