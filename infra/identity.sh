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

fed() { # name subject
  az ad app federated-credential list --id "$APP_ID" --query "[?name=='$1'] | length(@)" -o tsv | grep -q '^1$' && return
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"$1\", \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$2\", \"audiences\": [\"api://AzureADTokenExchange\"] }" -o none
}
echo "== Federated credentials"
fed github-main-branch "repo:${REPO}:ref:refs/heads/main"
fed github-pull-request "repo:${REPO}:pull_request"
for ENV in dev qa prod; do fed "github-env-${ENV}" "repo:${REPO}:environment:${ENV}"; done

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
