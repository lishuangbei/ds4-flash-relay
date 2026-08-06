#!/usr/bin/env bash
# 逐层探活，断在哪一环一目了然。可以在起网关前后都跑。
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

[ -f .env ] || { echo "缺 .env" >&2; exit 1; }
set -a; source .env; set +a

PORT="${LITELLM_PORT:-4000}"
ok=0; fail=0
chk() { if [ "$1" = 0 ]; then echo "  ✅ $2"; ok=$((ok+1)); else echo "  ❌ $2"; fail=$((fail+1)); fi; }

echo "[1/4] 到上游主机的 TCP 连通性"
# 不用 ping：容器里 ICMP 通常没权限，tailnet userspace 模式下也常不通，会误报。
host=$(echo "$DS4_API_BASE" | sed -E 's|https?://([^:/]+).*|\1|')
dport=$(echo "$DS4_API_BASE" | sed -nE 's|https?://[^:/]+:([0-9]+).*|\1|p'); dport="${dport:-8000}"
(exec 3<>"/dev/tcp/$host/$dport") 2>/dev/null; rc=$?; exec 3>&- 2>/dev/null; exec 3<&- 2>/dev/null
chk $rc "tcp $host:$dport"

echo "[2/4] ds4-server 端点"
body=$(curl -fsS --max-time 5 "$DS4_API_BASE/models" 2>/dev/null)
rc=$?
chk $rc "GET $DS4_API_BASE/models"
[ $rc = 0 ] && echo "$body" | python3 -c "
import sys,json
d=json.load(sys.stdin)['data'][0]
print(f\"       模型 {d['id']}  ctx {d.get('context_length','?')}\")" 2>/dev/null

echo "[3/4] ds4 实际推理（冷前缀可能要几十秒，耐心等）"
t0=$(date +%s)
out=$(curl -fsS --max-time 600 "$DS4_API_BASE/chat/completions" \
  -H 'content-type: application/json' \
  -H "authorization: Bearer $DS4_API_KEY" \
  -d '{"model":"deepseek-v4-flash","max_tokens":30,"think":false,"messages":[{"role":"user","content":"只回复两个字：正常"}]}' 2>/dev/null)
rc=$?; t1=$(date +%s)
chk $rc "chat/completions  ($((t1-t0))s)"
[ $rc = 0 ] && echo "$out" | python3 -c "
import sys,json; print('       回复:', json.load(sys.stdin)['choices'][0]['message']['content'].strip())" 2>/dev/null

echo "[4/4] LiteLLM 网关（没起就会失败，属正常）"
curl -fsS --max-time 5 "http://127.0.0.1:$PORT/health/liveliness" >/dev/null 2>&1
chk $? "网关 127.0.0.1:$PORT"

echo
echo "通过 $ok / 失败 $fail"
[ $fail -gt 0 ] && exit 1 || exit 0
