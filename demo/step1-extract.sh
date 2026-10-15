#!/usr/bin/env bash
# DEMO passo 2 (baseline): estrai l'API orders da APIM dev con il filtro.
set -euo pipefail; cd "$(dirname "$0")/.."; source demo/env.sh
npx apiops extract \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$RG_DEV" --service-name "$APIM_DEV" \
  --filter configuration.extractor.yaml \
  --output ./apim-artifacts
echo; echo "== Artefatti:"; find apim-artifacts -type f | sort
