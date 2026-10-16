# Runbook demo — APIOps in azione (Sharp4Dev 2026)

Tre istanze APIM Basic v2 (`apim-s4d-dev`, `apim-s4d-qa`, `apim-s4d-prod`), un repository GitHub pubblico, GitHub Actions con OIDC.
Versione CLI: **@azure-tools/apiops-cli 1.0.5** (pinnata in `package.json`).

## 0. Preparazione (almeno un giorno prima)

```bash
az login && az account set -s <subscription>
gh auth login
npm install                                   # installa la CLI pinnata (npx apiops …)

./infra/deploy.sh emanuele.garofalo@magneticode.com italynorth     # ~5-10 min per istanza Basic v2
```

Questa cartella è solo un insieme di file: il repository Git e quello su GitHub vanno creati **prima** di `identity.sh`, che scrive secret ed environment sul repo remoto. Dalla root della cartella:

```bash
git init -b main                                   # salta se hai già un .git
git add -A && git commit -m "chore: scaffolding apiops init + infra + demo"
gh repo create gar-ema/sharp4dev-2026-demo --public --description "APIOps in azione - demo Sharp4Dev 2026"
git remote add origin https://github.com/gar-ema/sharp4dev-2026-demo.git

./infra/identity.sh gar-ema/sharp4dev-2026-demo  # app registration, federated creds, RBAC, secret + environment GitHub
git push -u origin main
```

Il primo push fa già partire `promote.yml` (il trigger include `configuration.*.yaml`) con `apim-artifacts/` ancora vuota: se la run fallisce o è un no-op, ignorala, la baseline vera arriva al passo 2. Se hai `.git` dentro una cartella sincronizzata da OneDrive, aspetta che la sincronizzazione sia ferma prima di ogni commit.

Poi, nella UI di GitHub, una volta sola:

1. **Settings → Environments → prod → Required reviewers**: te stesso (e `qa` se vuoi due approvazioni in demo).
2. **Settings → Rules → Rulesets → New branch ruleset** (nei repo nuovi le branch protection classiche sotto "Branches" non ci sono più): enforcement *Active*, target *default branch*; regole: *Restrict deletions*, *Block force pushes*, *Require a pull request before merging* con **0 approvazioni** (sei l'unico collaboratore: GitHub non ti lascia approvare la tua PR, e "Require review from Code Owners" ti bloccherebbe al merge), *Require status checks to pass* → **`dry-run`** (è il nome del *job* in `pr-dry-run.yml`, non del workflow; compare nell'elenco dopo la prima run, prima si aggiunge digitandolo). In alternativa da terminale, ripetibile: il comando `gh api … /rulesets` in `.github/copilot-instructions.md` §9.
3. **Settings → Actions → General**: "Allow GitHub Actions to create and approve pull requests" (serve all'extractor per aprire PR).

Verifica: `./demo/smoke.sh dev` → orders, catalog (`X-Cache: HIT` alla seconda chiamata, 401/200 sul prezzo) e genai (che inoltra al finto modello `genai-mock` sullo stesso gateway) rispondono con `X-Environment: dev`; qa e prod ancora vuoti.
`./demo/chaos-test.sh` (503 casuali) e `./demo/genai-tokenlimit-test.sh` (429 dopo pochi prompt lunghi) sono i due test "wow" da tenere pronti.

> **Verificato in prova generale**: `llm-token-limit` non contava con il mock in `return-response` nella stessa inbound; ora `genai` inoltra a `genai-mock` (finto modello, stessa APIM) e il 429 scatta. Da dire in sala: "il gateway e il modello sono due cose diverse, anche nella demo".

Prova generale completa: esegui i passi 1-5 sotto, poi `./demo/reset.sh <email>` per tornare allo stato iniziale.
Tieni in una tab la run di `promote.yml` completata: è il piano B se Actions è lento in sala.

## 1. Scaffolding — 1 min (slide "1 · apiops init")

Tutto si fa **nel repo principale** (`apiops-sharp4dev-2026`, quello aperto in VS Code): è già l'output di `apiops init --ci github-actions --environments dev,qa,prod`, corretto in tre righe. Niente cartelle usa e getta, niente `cd` altrove.

Da VS Code, nell'Explorer, mostra cosa ha generato `init`: `.github/workflows/run-apiops-extractor.yml` e `run-apiops-publisher.yml`, `configuration.extractor.yaml`, i tre `configuration.<env>.yaml`, `APIOPS-WORKFLOW-IDENTITY-SETUP.md` e i **prompt file per Copilot** in `.github/prompts/`. Il comando è sulla slide, non serve rilanciarlo.

Cosa dire: due difetti reali della 1.0.5 che ho corretto a mano: il path filter `'./apim-artifacts/**'` (con `./` GitHub non lo matcha) e l'extractor generato che conosce solo dev/prod anche con `--environments dev,qa,prod`. Buon esempio di "progetto giovane: leggete ciò che genera".

## 2. Baseline — 3 min

```bash
./demo/step1-extract.sh
git add apim-artifacts && git commit -m "chore: baseline orders API from dev" && git push
```

Mostra l'albero: quattro API (orders, catalog, genai, genai-mock) con `apiInformation.json`, `specification.yaml`, `policy.xml` a livello API e operazione; `policyFragments/std-headers/` (arrivato come dipendenza transitiva: nessuno l'ha messo nel filtro); `backends/`, `namedValues/` (il segreto è `*** REDACTED ***`), `products/sharp4dev/apis.json`. Apri `apis/catalog/operations/list-products/policy.xml`: è la slide del muro delle policy, in XML.
Il push su main fa partire `promote.yml`: dev (no-op o PUT idempotenti) → qa → **si ferma in attesa di approvazione su prod**. Lascialo lì: approvi al passo 4.

> Primo deploy su qa/prod = tutte le risorse del commit (il commit di baseline le contiene tutte, quindi l'incrementale equivale a un full).

## 3. La modifica via PR — 4 min

```bash
./demo/step2-change.sh              # rate limit 5→20 su list-orders, header X-Api-Version nella policy API, branch feature/…
git commit -am "feat(orders): rate limit 20/min + X-Api-Version" && git push -u origin HEAD
gh pr create --fill --web
```

Nella PR: il diff XML leggibile; il check **PR dry-run** che commenta "✅ 2 PUT · 0 DELETE"; CODEOWNERS che richiede la review.
Se vuoi mostrare il gate: in una seconda PR cancella `products/sharp4dev/` → il commento diventa 🛑 e il check fallisce.

## 4. Merge → dev → qa → prod — 5 min

Merge della PR. `promote.yml`:

1. `publish-dev`: dry-run gate → publish `--commit-id <sha>`: solo le 2 policy cambiate (incrementale).
2. `publish-qa`: stesso commit, `configuration.qa.yaml` (backend URL qa, `env-name=qa`, token `ORDERS_BACKEND_KEY` dal secret dell'environment).
3. `publish-prod`: **in attesa di approvazione**. Apri la pagina, mostra "Review deployments", approva.

Mentre gira: `./demo/smoke.sh` → `X-Environment: dev / qa / prod` dalla stessa policy, valori diversi. `./demo/ratelimit-test.sh dev` → dopo la modifica servono 21 chiamate per un 429 (prima 6).

Cosa sottolineare: nessun segreto nel repo; chi ha approvato prod è nel log della run; il commit pubblicato è lo stesso SHA nei tre ambienti.

## 5. Drift (se avanza tempo) — 3 min

```bash
./demo/step5-drift.sh                # "hotfix" a mano in prod: rate limit 3
gh workflow run run-apiops-extractor.yml -f ENVIRONMENT=prod -f CONFIGURATION_YAML_PATH=configuration.extractor.yaml
```

Il workflow apre una PR `apim-extract-<run-id>` con il diff `calls="20"` → `calls="3"`. Decidi in review: accettare (merge → promuove ovunque) o rifiutare (chiudi la PR e ripubblichi: `gh workflow run promote.yml -f MODE=full`).
Nota: le PR aperte con `GITHUB_TOKEN` non fanno partire altri workflow (limite di GitHub), quindi su quella PR il dry-run non gira da solo: chiudi/riapri la PR o usa un PAT nell'extractor.

## Timing totale: 15-17 min. Tagli possibili: passo 1 (mostra solo i file), passo 5.

## Piano B

- Actions lento: tab con la run di `promote.yml` già completata + PR già commentata.
- Azure non risponde: `./demo/step3-dryrun-local.sh qa` da terminale (output di dry-run reale) e video registrato della promozione.
- Extract fallisce: `cp -r samples/codefirst/* apim-artifacts/` e continua dal passo 3.

## Dopo l'evento

`./infra/teardown.sh` — tre Basic v2 costano circa 0,2-0,3 €/ora ciascuna: non lasciarle accese.
