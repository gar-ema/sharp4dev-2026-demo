# Istruzioni per GitHub Copilot — repo `apiops-sharp4dev-2026`

Questo file spiega a Copilot (chat, agent mode, coding agent) il contesto completo del repository, le decisioni prese, le convenzioni e i punti ancora aperti, così da poter continuare il lavoro senza ricostruirlo. Leggilo per intero prima di proporre modifiche. Lingua di lavoro: **italiano** (commenti, commit, documentazione); i nomi di risorse, file e comandi restano in inglese.

## 1. Scopo del repository

> **Nomi**: repository GitHub `gar-ema/sharp4dev-2026-demo`; la cartella locale si chiama `apiops-sharp4dev-2026` (sincronizzata via OneDrive). Nei comandi `gh` e nelle federated credential usare sempre `gar-ema/sharp4dev-2026-demo`.

È la **demo live** del talk *"APIOps in azione: aggiungiamo agilità e governance alle tue API su Azure"* (Emanuele Garofalo, Sharp4Dev, 16 ottobre 2026, 40' + 5' Q&A). La demo occupa circa 12 minuti e deve dimostrare, su tre istanze reali di Azure API Management, che:

1. la **fonte di verità** della configurazione di APIM è il repository Git (`apim-artifacts/`);
2. la **pull request** è il punto di governance: il piano di `apiops publish --dry-run` viene commentato nella PR e un gate blocca le cancellazioni;
3. la **pipeline è l'unico scrittore** su APIM: lo stesso commit viene promosso dev → qa → prod con identità OIDC separate per ambiente, override per ambiente e approvazione manuale su prod.

Lo strumento è **APIOps CLI 1.0.5** (`@azure-tools/apiops-cli`, npm, Node ≥ 22), pinnato in `package.json`. Il vecchio APIOps Toolkit .NET (`Azure/apiops`) è in archiviazione: non usarlo e non proporlo. Il formato degli artefatti su disco è compatibile fra i due.

Il talk (slide, note, scaletta) vive **fuori** da questo repo, nella cartella OneDrive dell'evento (`APIOps-sharpcoding-v13.pptx`, `talk-notes.md`). Qui c'è solo ciò che serve alla demo.

## 2. Architettura della demo

```
APIM dev (seminata da Bicep) --apiops extract--> apim-artifacts/ --PR + dry-run--> main --promote.yml--> dev -> qa -> prod(approvazione)
```

- **Tre istanze APIM Basic v2**, una per ambiente, in tre resource group: `rg-apiops-s4d-{dev,qa,prod}`, istanze `apim-s4d-{dev,qa,prod}` (prefisso configurabile, parametro `namePrefix`). Regione usata: `italynorth`.
- **Solo dev viene seminata** da `infra/main.bicep` (`seedOrdersApi = (env == 'dev')`): è l'ambiente canonico da cui `apiops extract` produce gli artefatti. qa e prod ricevono configurazione **solo** via `apiops publish`: è il punto della demo, non seminarli mai da Bicep.
- **Nessun backend reale**: tutte le API rispondono da policy (`return-response` + espressioni C#). I backend (`orders-backend`, `catalog-backend`, `genai-backend`) esistono solo per mostrare gli override di URL per ambiente.
- **Tre API demo**, tutte senza subscription (`subscriptionRequired: false`), nel prodotto `sharp4dev`:
  - `orders` — `GET /orders`, `GET /orders/{id}`: `rate-limit-by-key` (5/min per IP, in demo viene alzato a 20 via PR), `set-backend-service`, `set-header X-Environment = {{env-name}}`, mock JSON. È l'API della modifica via PR (`demo/step2-change.sh`).
  - `catalog` — `GET /catalog/products[?chaos=true]`, `GET /catalog/products/{id}/price`: `include-fragment std-headers`, `cors`, `cache-lookup`/`cache-store` 20 s (cache interna di Basic v2), `check-header X-Client-Id` → 401, `choose` + `new Random()` → 503 casuali in chaos mode, `set-body` con StringBuilder. È il "muro delle policy" in pratica.
  - `genai` — `POST /genai/chat/completions` (schema OpenAI-compatible): `llm-token-limit` 300 TPM per IP con `estimate-prompt-tokens="true"`, risposta mock di chat completion con `usage`. Nel file di policy, **commentata**, c'è la versione di produzione (`set-backend-service` verso Foundry + `authentication-managed-identity`, `llm-emit-token-metric`, `llm-content-safety`). Non scommentarla: non c'è un deployment Foundry in demo.
- **Named value**: `env-name` (non segreto, valore = ambiente) e `orders-backend-key` (segreto: l'extract lo redige come `*** REDACTED ***`, in qa/prod arriva via token `{#[ORDERS_BACKEND_KEY]#}` sostituito dalla pipeline con il secret dell'environment GitHub).
- **Policy fragment** `std-headers` (X-Request-Id, X-Environment, X-Gateway): referenziato da catalog e genai; nel repo arriva come **dipendenza transitiva** del filtro dell'extractor, nessuno lo elenca esplicitamente. Questo è voluto, serve a mostrare la feature.

## 3. Mappa dei file

| Percorso | Cosa fa | Note per chi modifica |
|---|---|---|
| `infra/main.bicep` | Una APIM per ambiente + seed (solo dev) | Idempotente. Policy caricate con `loadTextContent` da `infra/policies/`. Le policy di operazione usano il nome completo `${apimName}/<api>/<op>/policy` con `dependsOn` (limite di Bicep sui parent condizionali). |
| `infra/*-openapi.yaml` | Spec OpenAPI 3 delle tre API | Gli `operationId` devono coincidere con i nomi usati nelle policy di operazione (`list-orders`, `get-order`, `list-products`, `get-price`, `chat-completions`). |
| `infra/policies/*.xml` | Policy a livello API, operazione e il fragment | Vedi §5 per le regole di scrittura. |
| `infra/deploy.sh <email> [location]` | Crea i tre RG e lancia il Bicep tre volte | ~5-10 min per istanza Basic v2 la prima volta. |
| `infra/identity.sh <owner/repo>` | App Registration `apiops-sharp4dev-github`, federated credentials (main, pull_request, environment dev/qa/prod), RBAC "API Management Service Contributor" per istanza + Reader sui RG, secret e environment GitHub via `gh` | Da rieseguire se cambia il repo. Richiede `az login` e `gh auth login`. |
| `infra/teardown.sh` | Cancella i tre RG | Da lanciare dopo l'evento: Basic v2 costa ~0,2-0,3 €/h per istanza. |
| `configuration.extractor.yaml` | Filtro: `apis: [orders, catalog, genai]`, `products: [sharp4dev]`, tutto il resto `[]` | Le dipendenze (backend, named value, fragment) arrivano da sole. Schema: `schemas/v1/extractor-config.schema.json` del repo apiops-cli. |
| `configuration.{dev,qa,prod}.yaml` | Override per ambiente: `namedValues` (env-name, orders-backend-key con token), `backends.url`, `apis.serviceUrl` | Il token `{#[ORDERS_BACKEND_KEY]#}` è sostituito in pipeline da `cschleiden/replace-tokens`; un passo di validazione fallisce se restano token non risolti. |
| `.github/workflows/pr-dry-run.yml` | Su PR che tocca `apim-artifacts/**` o `configuration.*.yaml`: dry-run su dev, commento in PR, gate "0 DELETE" | Vedi §6 sul formato JSON da verificare. |
| `.github/workflows/promote.yml` | Push su main → catena `publish-dev` → `publish-qa` → `publish-prod` (needs:), input `MODE=incremental|full` | Il job è il reusable `_publish-env.yml`. |
| `.github/workflows/_publish-env.yml` | Job riusabile: checkout `fetch-depth: 2`, Node 22, `npm ci`, `azure/login@v3` OIDC con `environment: <env>`, sostituzione token, **dry-run gate**, publish `--commit-id $GITHUB_SHA` (o full), smoke test | I secret per ambiente si chiamano `APIM_RESOURCE_GROUP_<ENV>`, `APIM_SERVICE_NAME_<ENV>`, `ORDERS_BACKEND_KEY` (environment). |
| `.github/workflows/run-apiops-{extractor,publisher}.yml` | Generati da `apiops init 1.0.5` e **patchati** (vedi §7) | L'extractor si usa per il drift (passo 5 della demo); il publisher è solo manuale, superato da promote.yml. |
| `.github/prompts/*.prompt.md`, `APIOPS-WORKFLOW-IDENTITY-SETUP.md` | Generati da `apiops init`: prompt file per Copilot e guida identità | Lasciarli: nel talk si cita che `init` genera prompt per Copilot. |
| `.github/CODEOWNERS` | Review obbligatoria su named value, prodotti, fragment, policy globale, API orders, override, workflow | Sostituire `@emanuelegarofalo` con il vero handle/team. |
| `apim-artifacts/` | Vuota (`.gitkeep`): la popola `apiops extract` nel passo 2 della demo | Non committare artefatti qui prima della demo, a meno che non si voglia saltare l'extract live. |
| `samples/codefirst/` | Gli stessi artefatti scritti a mano: **piano B** se l'extract live fallisce (`cp -r samples/codefirst/* apim-artifacts/`) | Deve restare allineato a `infra/policies/`: ogni fix a una policy va fatto in **entrambi** i posti. |
| `demo/RUNBOOK.md` | Script passo-passo della demo (5 passi, timing, piano B) | È il documento di riferimento per chi presenta; aggiornalo se cambi un passo. |
| `demo/env.sh` | Variabili comuni (`PREFIX`, RG, nomi APIM, `ORDERS_BACKEND_KEY`) | `source demo/env.sh` prima degli altri script. |
| `demo/step1-extract.sh` | `apiops extract` da dev con il filtro → `apim-artifacts/` | |
| `demo/step2-change.sh` | Branch `feature/…`, rate limit 5→20 su list-orders, header `X-Api-Version` nella policy API orders | La PR che ne nasce è il cuore della demo. |
| `demo/step3-dryrun-local.sh <env>` | Dry-run da terminale con gli override dell'ambiente | Piano B se GitHub Actions è lento. |
| `demo/step5-drift.sh` | "Hotfix" a mano su prod (rate limit 3) per mostrare il drift con l'extractor | Opzionale, se avanza tempo. |
| `demo/smoke.sh [env]`, `ratelimit-test.sh`, `chaos-test.sh`, `genai-tokenlimit-test.sh` | Test da terminale: header X-Environment, 429 del rate limit, 503 casuali, 429 del token limit | |
| `demo/reset.sh <email>` | Riporta dev allo stato iniziale (ri-applica il Bicep) e pulisce qa/prod | Dopo la prova generale. |
| `package.json` | Pinna `@azure-tools/apiops-cli@1.0.5` | Non usare `latest`. |

## 4. Stato dei lavori (15 ottobre 2026, sera prima dell'evento)

Fatto: repository completo, Bicep, policy, workflow, runbook, script. `npm install` OK (vedi §8 sull'audit).

In corso: **prova generale sul Mac di Emanuele**. Primo `infra/deploy.sh` fallito per un errore di validazione in `list-products.policy.xml` (`if` senza graffe, vedi §5); corretto, e nella stessa occasione la policy è stata riscritta con la cache a valore (§5). Da rilanciare. Non è ancora stato eseguito nulla su Azure oltre alla creazione del RG dev e del tentativo di deploy.

Da fare, in ordine:

1. `./infra/deploy.sh <email> italynorth` fino a tre istanze verdi; `./demo/smoke.sh dev` deve rispondere con `X-Environment: dev` su orders, catalog e genai.
2. Creare il repository (questa cartella non è un repo Git): `git init -b main`, commit, `gh repo create gar-ema/sharp4dev-2026-demo --public`, `git remote add origin …`; **poi** `./infra/identity.sh gar-ema/sharp4dev-2026-demo` (scrive secret ed environment sul repo remoto, quindi il repo deve esistere) e `git push -u origin main`; poi in GitHub: required reviewers su `prod`, ruleset su `main` con status check `dry-run` (§9), "Allow GitHub Actions to create and approve pull requests".
3. Prova generale completa seguendo `demo/RUNBOOK.md` passi 1-5, poi `demo/reset.sh`.
4. Verificare le due cose non testate (§6): forma del JSON di `--dry-run --format json` usata da `pr-dry-run.yml`, e comportamento di `llm-token-limit` con risposta mock.
5. Dopo l'evento: `./infra/teardown.sh`.

## 5. Regole per le policy APIM (errori già fatti, da non ripetere)

- Le **policy expression sono Razor/C#**: ogni `if`/`for` deve avere le graffe, anche con una sola istruzione. `if (i > 0) items.Append(",");` fa fallire il deploy con *"Expected a "{" but found a "items". Block statements must be enclosed in { }"*. Scrivere `if (i > 0) { items.Append(","); }`.
- In **attributi XML** gli operatori vanno escapati: `&amp;&amp;`, `&lt;`, `&gt;`, `&quot;`. Nel contenuto di un elemento (`<set-body>@{ … }</set-body>`) `<` va comunque scritto `&lt;`, `>` può restare.
- Usare solo i **tipi consentiti** nelle espressioni (System.Random, System.Text.StringBuilder, DateTime/DateTimeOffset, Guid, Linq… sono ammessi). Se il publish rifiuta `new Random()`, ripiegare su `Guid.NewGuid().GetHashCode()`.
- Ogni sezione (`inbound`, `backend`, `outbound`, `on-error`) deve contenere `<base />` dove si vuole ereditare dal livello superiore: la posizione di `<base />` decide l'ordine.
- Le policy mock usano `return-response` in `inbound`: ciò che segue nel ramo inbound non viene eseguito e **`outbound` non gira**. Per questo la coppia `cache-lookup`/`cache-store` (che lavora in inbound/outbound) **non funziona** con risposte mock: la prima versione di `list-products` aveva esattamente questo bug e il "cache hit" del runbook non sarebbe mai avvenuto. Corretto con la cache a valore, tutta in inbound: `cache-lookup-value` → se la variabile manca genera body e timestamp e li salva con `cache-store-value` (20 s) → `return-response` con header `X-Cache: HIT|MISS` e `X-Generated-At`. Mantenere questo schema per qualunque altra risposta mock da mettere in cache.
- Qualunque fix a `infra/policies/X.xml` va replicato in `samples/codefirst/.../policy.xml` (stesso contenuto). Un `diff -r` fra i due set è un buon check.

## 6. Punti non ancora verificati (da provare prima di fidarsi)

- **Formato JSON del dry-run.** `pr-dry-run.yml` legge `jq '.dryRun.summary.deletes'`, `.creates`, `.skips`. Questa forma è stata dedotta dalla documentazione di apiops-cli 1.0.5, non osservata. Al primo run reale: salvare l'output di `npx apiops publish … --dry-run --format json`, adeguare i path `jq` e il testo del commento. Lo stesso vale per il nome delle azioni (PUT/PATCH/DELETE/SKIP) citato nel runbook.
- **`llm-token-limit` con mock.** La stima del prompt avviene prima della chiamata al backend, quindi il 429 dovrebbe scattare anche senza backend; se la policy non conta i token di completamento della risposta mock, alzare il prompt in `demo/genai-tokenlimit-test.sh`.
- **Cache di catalog**: verificare che la seconda chiamata a `GET /catalog/products` entro 20 s risponda `X-Cache: HIT` con lo stesso `X-Generated-At` (`demo/smoke.sh dev`).
- **Behaviour di `--commit-id` al primo publish su qa/prod**: il commit di baseline contiene tutti gli artefatti, quindi l'incrementale equivale a un full. Se qa/prod risultano vuoti dopo il primo promote, lanciare `gh workflow run promote.yml -f MODE=full`.
- **PR aperte da `GITHUB_TOKEN`** (extractor, passo 5) non fanno partire `pr-dry-run.yml`: è un limite di GitHub. Chiudere/riaprire la PR o usare un PAT nell'extractor.

## 7. Difetti reali di `apiops init` 1.0.5 trovati e corretti (da citare nel talk, non da "ripulire")

1. Path filter generato come `'./apim-artifacts/**'`: con `./` GitHub Actions non lo matcha. Corretto in `'apim-artifacts/**'`.
2. L'extractor generato conosce solo `dev` e `prod` anche con `--environments dev,qa,prod`. Aggiunto `qa`.
3. `package.json` generato con `"latest"`. Pinnato a `1.0.5`.

Sono esempi voluti di "progetto giovane: leggete ciò che genera". Se una versione successiva della CLI li risolve, aggiornare questa sezione, non cancellarla.

## 8. Dipendenze e sicurezza

`npm audit` segnala 1 high + 2 critical, tutte in **simple-git** (dipendenza transitiva della CLI per `git diff` in `--commit-id`): advisory sul bypass del guard "unsafe operations" con input non fidato negli argomenti git. Fix disponibile solo in simple-git 4.x (major): la CLI 1.0.5 dichiara `^3.35.2`, quindi `npm audit fix` non può applicarlo. **Non** forzare l'upgrade con `overrides` prima dell'evento: rischia di rompere `--commit-id`. L'input che arriva a git in questo repo è `GITHUB_SHA`, non input utente: il rischio è accettato. Ricontrollare se esce una release della CLI > 1.0.5.

## 9. Protezione di `main` (ruleset)

Nei repository nuovi GitHub non mostra più le branch protection classiche (Settings → Branches): si usano i **Rulesets** (Settings → Rules → Rulesets → New branch ruleset). Scelte fatte per la demo, da non "irrigidire" senza motivo:

- **0 approvazioni richieste** e niente "Require review from Code Owners": Emanuele è l'unico collaboratore e GitHub non permette di approvare la propria PR; con 1 approvazione la demo si blocca al merge. CODEOWNERS resta nel repo come racconto ("in un team vero qui scatta la review").
- **Status check richiesto: `dry-run`**, cioè il *job id* di `pr-dry-run.yml` (il check prende il nome del job, non del workflow). Se rinomini il job o aggiungi `name:` al job, aggiorna il ruleset.
- Bypass per il ruolo *Repository admin*: in sala, in emergenza, si può pushare su main saltando la regola.

Creazione da terminale (se il ruleset esiste già, aggiornalo con `PUT repos/gar-ema/sharp4dev-2026-demo/rulesets/<id>`):

```bash
gh api -X POST repos/gar-ema/sharp4dev-2026-demo/rulesets --input - <<'JSON'
{
  "name": "main: PR + dry-run gate",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["merge", "squash", "rebase"] } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [ { "context": "dry-run" } ] } }
  ],
  "bypass_actors": [ { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" } ]
}
JSON
```

## 10. Convenzioni

- Commit in italiano con prefisso conventional (`feat(orders): …`, `chore: …`, `fix(policies): …`). I commit della demo live hanno messaggi già scritti nel runbook: non cambiarli senza aggiornare il runbook.
- Non committare mai segreti né artefatti con valori reali: il named value segreto resta `*** REDACTED ***` nel repo.
- Non cambiare nomi di RG, istanze, environment o secret senza aggiornare in blocco `demo/env.sh`, `infra/identity.sh`, i workflow e il runbook: sono accoppiati per nome.
- Prima di una PR che tocca `infra/policies/`, validare l'XML (`xmllint --noout`) e cercare `if (`/`for (` senza graffe.
- Script bash: `set -euo pipefail`, compatibili con macOS (bash 3.2: niente array associativi, `sed -i ''`).

## 11. Cosa NON fare

- Non seminare qa/prod da Bicep, non usare `--delete-unmatched` in pipeline, non pubblicare da locale su prod: romperebbe la narrativa della demo (pipeline unico scrittore).
- Non sostituire la CLI con il Toolkit .NET o con script `az apim`.
- Non riscrivere i workflow generati da `init` da zero: sono mostrati nel talk come output dello scaffolding; le estensioni stanno in `promote.yml` e `_publish-env.yml`.
- Non rimuovere `samples/codefirst/`: è il piano B.

## 12. Riferimenti

- APIOps CLI: https://github.com/Azure/apiops-cli (docs, CHANGELOG, schemi JSON in `schemas/v1/`)
- Microsoft Learn: *How to manage API Management configuration with APIOps CLI*; Architecture Center: *Automate API Management configuration by using APIOps CLI*
- Policy reference APIM (sezioni, scope, `<base />`, tipi consentiti nelle espressioni, policy `llm-*`)
- Runbook e piano B: `demo/RUNBOOK.md`
