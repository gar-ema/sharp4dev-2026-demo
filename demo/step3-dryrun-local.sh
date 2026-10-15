#!/usr/bin/env bash
# Dry-run locale verso qa o prod (per mostrare il report senza aspettare la pipeline). Uso: ./demo/step3-dryrun-local.sh qa|prod [--format json]
set -euo pipefail; cd "$(dirname "$0")/.."; source demo/env.sh
ENV="${1:-qa}"; shift || true; U=$(echo "$ENV" | tr a-z A-Z); RG="RG_$U"; APIM="APIM_$U"
# sostituzione token locale su una copia (non committare mai il file risolto)
sed "s/{#\[ORDERS_BACKEND_KEY\]#}/${ORDERS_BACKEND_KEY}/" "configuration.${ENV}.yaml" > "configuration.${ENV}.local.yaml"
npx apiops publish \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "${!RG}" --service-name "${!APIM}" \
  --source ./apim-artifacts --overrides "configuration.${ENV}.local.yaml" \
  --dry-run "$@"
