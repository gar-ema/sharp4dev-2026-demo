# Variabili comuni della demo. `source demo/env.sh`
export PREFIX="${PREFIX:-apim-s4d}"
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
export RG_DEV="rg-apiops-s4d-dev";  export APIM_DEV="${PREFIX}-dev"
export RG_QA="rg-apiops-s4d-qa";    export APIM_QA="${PREFIX}-qa"
export RG_PROD="rg-apiops-s4d-prod"; export APIM_PROD="${PREFIX}-prod"
export ORDERS_BACKEND_KEY="${ORDERS_BACKEND_KEY:-local-dev-key}"
