#!/bin/bash
# 启动 Claude Code，固定走本地 ds4-flash-0731（经 local-llm 网关）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 密钥不进 git：从同目录 .env.local（gitignored）读，或者预先 export DS4_GATEWAY_KEY
[ -f "$HERE/.env.local" ] && . "$HERE/.env.local"

GATEWAY="${DS4_GATEWAY:-http://172.17.0.2:4000}"
KEY="${DS4_GATEWAY_KEY:?缺网关 key：在 $HERE/.env.local 写 DS4_GATEWAY_KEY=<LITELLM_MASTER_KEY>，或先 export}"
MODEL="${DS4_MODEL:-deepseek-v4-flash}"
# 必须明显低于 ds4-server 的 --ctx（缓冲吸收单轮工具结果突刺 + 生成输出）。
# 服务端 110K(112640) 时取 90000（缓冲约 22K）。
# 调服务端 ctx 时同步三处：这里(.env.local)、.claude/settings.json、Mac 的 config.sh。
COMPACT_WINDOW="${DS4_COMPACT_WINDOW:-90000}"

# 起手探活：直接验证 Claude Code 要用的 /v1/messages 端点本身。
# 失败就带原因退出，不让 claude 起来再报一堆难懂的连接错。
resp=$(curl -fsS --max-time 60 "$GATEWAY/v1/messages" \
  -H "x-api-key: $KEY" -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "{\"model\":\"$MODEL\",\"max_tokens\":1,\"think\":false,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" \
  2>&1) || { echo "网关 /v1/messages 探活失败: $resp" >&2; exit 1; }
case "$resp" in
  *'"content"'*) ;;
  *) echo "响应格式不对（LiteLLM 的 Anthropic 端点可能没生效）: ${resp:0:200}" >&2; exit 1 ;;
esac

# 防止 shell 里残留的真 Anthropic key 压过 AUTH_TOKEN（API_KEY 优先级更高）
unset ANTHROPIC_API_KEY

export ANTHROPIC_BASE_URL="$GATEWAY"
export ANTHROPIC_AUTH_TOKEN="$KEY"
export ANTHROPIC_MODEL="$MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL"
export CLAUDE_CODE_SUBAGENT_MODEL="$MODEL"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_STREAM_IDLE_TIMEOUT_MS=600000
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="$COMPACT_WINDOW"

exec claude --dangerously-skip-permissions "$@"
