# Artefatti code-first (fallback)

Versione scritta a mano degli artefatti che `apiops extract` produce dall'APIM dev seminata da `infra/main.bicep`.
Serve come piano B se l'estrazione live fallisce: `cp -r samples/codefirst/* apim-artifacts/`.

**Attenzione:** il formato è ricavato da `docs/reference/artifact-format.md` e `docs/guides/code-first-workflow.md` di apiops-cli 1.0.5.
L'output reale dell'extract può contenere campi in più (es. `apiRevision`, `isCurrent`, `type`): dopo la prima estrazione vera,
confronta e aggiorna questa cartella (`diff -r samples/codefirst apim-artifacts`).
