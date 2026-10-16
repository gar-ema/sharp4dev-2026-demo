#!/usr/bin/env bash
# DEMO passo 3 (la modifica): alza il rate limit 5 → 20 sull'operazione list-orders
# e aggiunge un header di versione nella policy dell'API. Poi apre un branch.
set -euo pipefail; cd "$(dirname "$0")/.."
P=apim-artifacts/apis/orders/operations/list-orders/policy.xml
[ -f "$P" ] || { echo "Prima esegui demo/step1-extract.sh"; exit 1; }
git checkout -b feature/orders-ratelimit-20 2>/dev/null || git checkout feature/orders-ratelimit-20
sed -i '' 's/rate-limit-by-key calls="5"/rate-limit-by-key calls="20"/' "$P"
python3 - <<'PY'
import re
p='apim-artifacts/apis/orders/policy.xml'; s=open(p, newline='').read()
if 'X-Api-Version' not in s:
    # l'extract scrive tab e CRLF: si riusano indentazione e fine riga trovati nel file
    nl = '\r\n' if '\r\n' in s else '\n'
    m = re.search(r'(<outbound>\r?\n)([ \t]*)(<base />)', s)
    ind = m.group(2)
    block = f'{ind}<set-header name="X-Api-Version" exists-action="override">{nl}{ind}{ind[:1] or " "}<value>1.1</value>{nl}{ind}</set-header>'
    s = s[:m.end()] + nl + block + s[m.end():]
    open(p, 'w', newline='').write(s)
PY
git --no-pager diff --stat; echo; git --no-pager diff
echo; echo "Ora: git commit -am 'feat(orders): rate limit 20/min + X-Api-Version' && git push -u origin HEAD && gh pr create --fill"
