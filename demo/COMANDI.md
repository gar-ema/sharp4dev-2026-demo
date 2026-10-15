# Demo

Dalla root del repo, salvo dove indicato.

## Cosa ho fatto prima di salire sul palco?

```bash
az login && az account set -s <subscription>
gh auth status
./demo/smoke.sh dev          # 200 + X-Environment: dev su orders, catalog, genai
ls apim-artifacts            # deve essere vuota (solo .gitkeep)
```

## 1. Scaffolding

```bash
DEMO_INIT="/Users/garema/Library/CloudStorage/OneDrive-Magneticode/Community/2026/20261016-sharp4dev 2026/sharp4dev2026-demo"
mkdir -p "$DEMO_INIT" && cd "$DEMO_INIT" && git init -q
npx @azure-tools/apiops-cli@1.0.5 init --ci github-actions --environments dev,qa,prod --non-interactive
find . -not -path './.git*' -type f | sort
cd -
```

## 2. Demo 1 estrazione

```bash
./demo/step1-extract.sh
git add apim-artifacts && git commit -m "chore: baseline orders API from dev" && git push
gh run watch                 # promote.yml: dev → qa → attesa approvazione prod (lasciala lì)
```

## 3. Modifica via PR

```bash
./demo/step2-change.sh
git commit -am "feat(orders): rate limit 20/min + X-Api-Version" && git push -u origin HEAD
gh pr create --fill --web
gh pr checks --watch         # dry-run + commento in PR
```

## 4. Merge e promozione

```bash
gh pr merge --merge
gh run watch                 # poi approva prod dalla UI: "Review deployments"
./demo/smoke.sh              # X-Environment: dev / qa / prod
./demo/ratelimit-test.sh dev # 429 solo dopo 20 chiamate
```

Test "wow" (quando vuoi):

```bash
./demo/chaos-test.sh
./demo/genai-tokenlimit-test.sh   # 5×200 poi 429
```

## 5. Drift (se avanza tempo)

```bash
./demo/step5-drift.sh
gh workflow run run-apiops-extractor.yml -f ENVIRONMENT=prod -f CONFIGURATION_YAML_PATH=configuration.extractor.yaml
gh pr list                   # PR apim-extract-<run-id>: calls="20" → "3"
gh workflow run promote.yml -f MODE=full   # solo se rifiuti il drift
```

## Piano B

```bash
cp -r samples/codefirst/* apim-artifacts/   # extract fallito → riparti dal passo 3
./demo/step3-dryrun-local.sh qa             # Actions/Azure lenti: dry-run da terminale
```

## Dopo l'evento

```bash
./infra/teardown.sh
```
