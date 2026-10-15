#!/usr/bin/env bash
# Riporta la demo allo stato iniziale (da usare tra una prova e l'altra):
#  - dev: ri-esegue il Bicep (rate limit 5, policy originali)
#  - qa/prod: rimuove API, prodotto, backend e named value pubblicati
#  - repo: svuota apim-artifacts e torna su main
set -euo pipefail; cd "$(dirname "$0")/.."; source demo/env.sh
EMAIL="${1:?publisher email (serve al Bicep)}"
echo "== dev: redeploy seed"; az deployment group create -g "$RG_DEV" -n apim-dev -f infra/main.bicep -p env=dev namePrefix="$PREFIX" publisherEmail="$EMAIL" -o none
for ENV in qa prod; do
  U=$(echo "$ENV" | tr a-z A-Z); RG="RG_$U"; APIM="APIM_$U"
  echo "== ${ENV}: pulizia"
  for API in orders catalog genai; do
    az apim product api delete -g "${!RG}" -n "${!APIM}" --product-id sharp4dev --api-id "$API" -o none 2>/dev/null || true
    az apim api delete -g "${!RG}" -n "${!APIM}" --api-id "$API" --delete-revisions true -y -o none 2>/dev/null || true
  done
  az apim product delete -g "${!RG}" -n "${!APIM}" --product-id sharp4dev --delete-subscriptions true -y -o none 2>/dev/null || true
  for NV in env-name orders-backend-key; do az apim nv delete -g "${!RG}" -n "${!APIM}" --named-value-id "$NV" -y -o none 2>/dev/null || true; done
  for BE in orders-backend catalog-backend genai-backend; do
    az rest --method delete --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${!RG}/providers/Microsoft.ApiManagement/service/${!APIM}/backends/${BE}?api-version=2024-06-01-preview" -o none 2>/dev/null || true
  done
  az rest --method delete --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${!RG}/providers/Microsoft.ApiManagement/service/${!APIM}/policyFragments/std-headers?api-version=2024-06-01-preview" -o none 2>/dev/null || true
done
echo "== repo"; git checkout -q main; git pull -q; rm -rf apim-artifacts/*; touch apim-artifacts/.gitkeep; rm -f configuration.*.local.yaml
git branch -D feature/orders-ratelimit-20 2>/dev/null || true
echo "Reset completato. Se la PR/branch esiste su GitHub: gh pr close --delete-branch"
