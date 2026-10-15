#!/usr/bin/env bash
# Crea i tre resource group e le tre istanze APIM (Basic v2). Idempotente.
# Uso: ./infra/deploy.sh <publisher-email> [location] [namePrefix]
set -euo pipefail
EMAIL="${1:?publisher email}"; LOCATION="${2:-italynorth}"; PREFIX="${3:-apim-s4d}"
cd "$(dirname "$0")"
for ENV in dev qa prod; do
  RG="rg-apiops-s4d-${ENV}"
  APIM="${PREFIX}-${ENV}"
  DEPLOYMENT="apim-${ENV}"

  # RG esistente: si riusa nella sua regione (un RG non si può spostare)
  RG_LOCATION="$(az group show -n "$RG" --query location -o tsv 2>/dev/null || true)"
  if [[ -n "$RG_LOCATION" ]]; then
    echo "== ${ENV}: resource group ${RG} già presente in ${RG_LOCATION}"
    if [[ "$RG_LOCATION" != "$LOCATION" ]]; then
      echo "   attenzione: richiesto ${LOCATION}, uso ${RG_LOCATION}"
    fi
  else
    echo "== ${ENV}: resource group ${RG} in ${LOCATION}"
    az group create -n "$RG" -l "$LOCATION" -o none --tags event=sharp4dev-2026 env="$ENV"
    RG_LOCATION="$LOCATION"
  fi

  # APIM cancellata di recente resta in soft-delete e blocca la ricreazione con lo stesso nome
  if [[ -z "$(az apim show -g "$RG" -n "$APIM" --query name -o tsv 2>/dev/null || true)" ]] &&
     [[ -n "$(az apim deletedservice show -n "$APIM" -l "$RG_LOCATION" --query name -o tsv 2>/dev/null || true)" ]]; then
    echo "== ${ENV}: ${APIM} in soft-delete, purge"
    az apim deletedservice purge -n "$APIM" -l "$RG_LOCATION"
  fi

  # Un deployment precedente ancora in corso farebbe fallire il nuovo con Conflict
  STATE="$(az deployment group show -g "$RG" -n "$DEPLOYMENT" --query properties.provisioningState -o tsv 2>/dev/null || true)"
  if [[ "$STATE" == "Running" || "$STATE" == "Accepted" ]]; then
    echo "== ${ENV}: deployment ${DEPLOYMENT} ancora in corso, attendo"
    az deployment group wait -g "$RG" -n "$DEPLOYMENT" --interval 30 \
      --custom "properties.provisioningState!='Running' && properties.provisioningState!='Accepted'"
  fi

  echo "== ${ENV}: deploy APIM ${APIM} (Basic v2, qualche minuto)"
  az deployment group create -g "$RG" -n "$DEPLOYMENT" -f main.bicep \
    -p env="$ENV" namePrefix="$PREFIX" publisherEmail="$EMAIL" \
    --query "properties.outputs.{name:apimName.value,gateway:gatewayUrl.value}" -o table
done
echo
echo "Fatto. Prossimo passo: ./infra/identity.sh <github-owner/repo> [namePrefix]"
