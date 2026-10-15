#!/usr/bin/env bash
# Cancella tutto (resource group + app registration). Chiede conferma.
set -euo pipefail
read -r -p "Cancello rg-apiops-s4d-{dev,qa,prod} e l'app registration apiops-sharp4dev-github? [y/N] " a
[ "$a" = "y" ] || exit 0
for ENV in dev qa prod; do az group delete -n "rg-apiops-s4d-${ENV}" --yes --no-wait; done
APP_ID=$(az ad app list --display-name apiops-sharp4dev-github --query "[0].appId" -o tsv)
[ -n "$APP_ID" ] && az ad app delete --id "$APP_ID"
echo "Cancellazione avviata (APIM impiega qualche minuto; Basic v2 non ha soft-delete lungo come i tier classici, verifica con 'az apim deletedservice list')."
