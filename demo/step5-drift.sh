#!/usr/bin/env bash
# DEMO passo 6 (drift): modifica "a mano" la policy di list-orders in PROD (rate limit 20 → 3),
# come farebbe un hotfix dal portale. Poi lancia il workflow di extract su prod che apre una PR con la differenza.
set -euo pipefail; cd "$(dirname "$0")/.."; source demo/env.sh
az rest --method put \
  --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RG_PROD}/providers/Microsoft.ApiManagement/service/${APIM_PROD}/apis/orders/operations/list-orders/policies/policy?api-version=2024-06-01-preview" \
  --body "$(python3 -c "import json;print(json.dumps({'properties':{'format':'rawxml','value':open('apim-artifacts/apis/orders/operations/list-orders/policy.xml').read().replace('calls=\"20\"','calls=\"3\"')}}))")" -o none
echo "Drift introdotto in prod (calls=3). Ora: gh workflow run run-apiops-extractor.yml -f ENVIRONMENT=prod -f CONFIGURATION_YAML_PATH=configuration.extractor.yaml"
