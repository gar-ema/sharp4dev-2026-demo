#!/usr/bin/env bash
# Identità per GitHub Actions: App Registration + federated credentials (main + 3 environment)
# + RBAC sulle tre APIM + secret e environment su GitHub (richiede `gh auth login`).
# Uso: ./infra/identity.sh <owner/repo> [namePrefix]
set -euo pipefail
REPO="${1:?owner/repo}"; PREFIX="${2:-apim-s4d}"
APP_NAME="apiops-sharp4dev-github"
SUB_ID=$(az account show --query id -o tsv); TENANT_ID=$(az account show --query tenantId -o tsv)

echo "== App registration ${APP_NAME}"
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
if [ -z "$APP_ID" ]; then
  APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
  az ad sp create --id "$APP_ID" -o none
fi
echo "   clientId = $APP_ID"

fed() { # name subject — crea, o ricrea se il subject è cambiato
  local CUR
  CUR=$(az ad app federated-credential list --id "$APP_ID" --query "[?name=='$1'].subject | [0]" -o tsv)
  [ "$CUR" = "$2" ] && return
  if [ -n "$CUR" ]; then
    az ad app federated-credential delete --id "$APP_ID" --federated-credential-id "$1"
  fi
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"$1\", \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$2\", \"audiences\": [\"api://AzureADTokenExchange\"] }" -o none
}
echo "== Federated credentials"
# GitHub può emettere il subject classico (owner/repo) o quello con gli ID (owner@id/repo@id): li registriamo entrambi
OWNER="${REPO%%/*}"; NAME="${REPO##*/}"
OWNER_ID=$(gh api "users/${OWNER}" -q .id); REPO_ID=$(gh api "repos/${REPO}" -q .id)
for P in "classic:repo:${REPO}" "ids:repo:${OWNER}@${OWNER_ID}/${NAME}@${REPO_ID}"; do
  K="${P%%:*}"; S="${P#*:}"; SFX=""; [ "$K" = ids ] && SFX="-ids"
  fed "github-main-branch${SFX}" "${S}:ref:refs/heads/main"
  fed "github-pull-request${SFX}" "${S}:pull_request"
  for ENV in dev qa prod; do fed "github-env-${ENV}${SFX}" "${S}:environment:${ENV}"; done
done

echo "== RBAC: API Management Service Contributor sulle istanze, Reader sui resource group"
for ENV in dev qa prod; do
  RG="rg-apiops-s4d-${ENV}"; APIM="${PREFIX}-${ENV}"
  SCOPE="/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.ApiManagement/service/${APIM}"
  az role assignment create --assignee "$APP_ID" --role "API Management Service Contributor" --scope "$SCOPE" -o none 2>/dev/null || true
  az role assignment create --assignee "$APP_ID" --role "Reader" --scope "/subscriptions/${SUB_ID}/resourceGroups/${RG}" -o none 2>/dev/null || true
done

echo "== GitHub: secret di repository + environment (dev, qa, prod)"
gh secret set AZURE_CLIENT_ID -R "$REPO" -b "$APP_ID"
gh secret set AZURE_TENANT_ID -R "$REPO" -b "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID -R "$REPO" -b "$SUB_ID"
for ENV in dev qa prod; do
  U=$(echo "$ENV" | tr a-z A-Z)
  gh api -X PUT "repos/${REPO}/environments/${ENV}" --silent
  gh secret set "APIM_RESOURCE_GROUP_${U}" -R "$REPO" -b "rg-apiops-s4d-${ENV}"
  gh secret set "APIM_SERVICE_NAME_${U}" -R "$REPO" -b "${PREFIX}-${ENV}"
  gh secret set "APIM_RESOURCE_GROUP_${U}" -R "$REPO" --env "$ENV" -b "rg-apiops-s4d-${ENV}"
  gh secret set "APIM_SERVICE_NAME_${U}" -R "$REPO" --env "$ENV" -b "${PREFIX}-${ENV}"
  gh secret set ORDERS_BACKEND_KEY -R "$REPO" --env "$ENV" -b "${ENV}-secret-$(openssl rand -hex 6)"
done
echo
echo "Manca solo (via UI, una volta): Settings → Environments → prod → Required reviewers (e volendo qa)."
echo "RBAC può impiegare qualche minuto a propagarsi."
