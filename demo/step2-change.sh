#!/usr/bin/env bash
# DEMO passo 3 (la modifica): alza il rate limit 5 → 20 sull'operazione list-orders
# e aggiunge un header di versione nella policy dell'API. Poi apre un branch.
set -euo pipefail; cd "$(dirname "$0")/.."
P=apim-artifacts/apis/orders/operations/list-orders/policy.xml
[ -f "$P" ] || { echo "Prima esegui demo/step1-extract.sh"; exit 1; }
git checkout -b feature/orders-ratelimit-20 2>/dev/null || git checkout feature/orders-ratelimit-20
sed -i 's/rate-limit-by-key calls="5"/rate-limit-by-key calls="20"/' "$P"
python3 - <<'PY'
import re,io
p='apim-artifacts/apis/orders/policy.xml'; s=open(p).read()
if 'X-Api-Version' not in s:
    s=s.replace('<outbound>\n        <base />','<outbound>\n        <base />\n        <set-header name="X-Api-Version" exists-action="override">\n            <value>1.1</value>\n        </set-header>',1)
    open(p,'w').write(s)
PY
git --no-pager diff --stat; echo; git --no-pager diff
echo; echo "Ora: git commit -am 'feat(orders): rate limit 20/min + X-Api-Version' && git push -u origin HEAD && gh pr create --fill"
