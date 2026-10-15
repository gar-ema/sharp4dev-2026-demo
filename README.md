# APIOps in azione — demo Sharp4Dev 2026

Repository della demo del talk *"APIOps in azione: aggiungiamo agilità e governance alle tue API su Azure"* (Emanuele Garofalo, Sharp4Dev 2026).

Mostra come gestire la configurazione di **Azure API Management** come codice con **[APIOps CLI](https://github.com/Azure/apiops-cli) 1.0.5** e promuoverla attraverso tre ambienti (dev → qa → prod) con GitHub Actions, OIDC e approvazioni.

```
┌──────────┐  apiops extract   ┌──────────────┐   PR + dry-run   ┌──────┐  promote.yml  ┌─────┐ ┌─────┐ ┌──────┐
│ APIM dev │ ────────────────▶ │ apim-artifacts│ ───────────────▶ │ main │ ────────────▶ │ dev │▶│ qa  │▶│ prod │
│ (seed)   │                   │ + overrides   │                  └──────┘  --commit-id  └─────┘ └─────┘ └──────┘
└──────────┘                   └──────────────┘                                                     ▲ approval
```

## Struttura

| Percorso | Cosa |
|---|---|
| `infra/` | Bicep per le tre APIM Basic v2 (dev seminata con le API `orders`, `catalog`, `genai` e il fragment `std-headers`), script `deploy.sh`, `identity.sh` (OIDC + RBAC + secret GitHub), `teardown.sh` |
| `apim-artifacts/` | Artefatti APIM (vuoto: li produce `apiops extract` durante la demo) |
| `configuration.extractor.yaml` | Filtro: le tre API demo e il prodotto `sharp4dev` (+ dipendenze transitive: backend, named value, fragment) |
| `configuration.{dev,qa,prod}.yaml` | Override per ambiente: URL backend, `serviceUrl`, named value `env-name`, segreto via token `{#[ORDERS_BACKEND_KEY]#}` |
| `.github/workflows/pr-dry-run.yml` | Su ogni PR: `apiops publish --dry-run` su dev, commento con il piano, gate "0 DELETE" |
| `.github/workflows/promote.yml` + `_publish-env.yml` | Promozione dev → qa → prod dello stesso commit, dry-run gate per ambiente, approvazione su prod |
| `.github/workflows/run-apiops-{extractor,publisher}.yml` | Generati da `apiops init` (extractor usato per il drift; publisher solo manuale) |
| `.github/prompts/` | Prompt file per GitHub Copilot generati da `apiops init` |
| `demo/` | `RUNBOOK.md` passo-passo, script dei singoli passi, `smoke.sh`, `chaos-test.sh`, `genai-tokenlimit-test.sh`, `reset.sh` |
| `samples/codefirst/` | Artefatti scritti a mano: piano B se l'extract live fallisce |

## Le API della demo (tutte mock: nessun backend reale, risposte casuali generate dalle policy)

| API | Operazioni | Policy mostrate |
|---|---|---|
| `orders` | `GET /orders`, `GET /orders/{id}` | `rate-limit-by-key`, `set-backend-service`, `set-header` con named value `{{env-name}}`, `return-response` |
| `catalog` | `GET /catalog/products[?chaos=true]`, `GET /catalog/products/{id}/price` | `include-fragment` (std-headers), `cors`, `cache-lookup-value`/`cache-store-value` (20 s), `check-header` (401), `set-variable` + `choose` + `Random` (503 casuali), `set-body` con espressioni C# |
| `genai` | `POST /genai/chat/completions` (schema OpenAI) | `llm-token-limit` (300 TPM per IP, stima del prompt), mock di chat completion con `usage`; in commento la versione prod: `set-backend-service` + `authentication-managed-identity` verso Foundry, `llm-emit-token-metric`, `llm-content-safety` |

## Quick start

```bash
az login && gh auth login && npm install
./infra/deploy.sh <publisher-email> italynorth
git init -b main && git add -A && git commit -m "chore: scaffolding"
gh repo create gar-ema/sharp4dev-2026-demo --public && git remote add origin https://github.com/gar-ema/sharp4dev-2026-demo.git
./infra/identity.sh gar-ema/sharp4dev-2026-demo
git push -u origin main
# poi: GitHub → Settings → Environments → prod → Required reviewers
./demo/step1-extract.sh && git add apim-artifacts && git commit -m "chore: baseline" && git push
```

Segui `demo/RUNBOOK.md`.

## Riferimenti

- [APIOps CLI — docs](https://github.com/Azure/apiops-cli/tree/main/docs) · [CHANGELOG](https://github.com/Azure/apiops-cli/blob/main/CHANGELOG.md)
- [How to manage API Management configuration with APIOps CLI](https://learn.microsoft.com/azure/api-management/how-to-manage-apiops-cli)
- [Automate API Management configuration by using APIOps CLI (Architecture Center)](https://learn.microsoft.com/azure/architecture/example-scenario/devops/automated-api-deployments-apiops)

Licenza MIT.

## Per chi continua il lavoro (umani e Copilot)

Contesto completo, decisioni, errori già fatti e punti aperti sono in [`.github/copilot-instructions.md`](.github/copilot-instructions.md): GitHub Copilot lo legge automaticamente, ma vale la lettura anche per le persone.
