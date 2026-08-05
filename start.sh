#!/usr/bin/env bash
# 启动 LiteLLM 网关。其他容器打 http://local-llm:<port>/v1
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

[ -f .env ] || { echo "缺 .env —— 先 cp .env.example .env 并填好" >&2; exit 1; }
set -a; source .env; set +a

[ "$LITELLM_MASTER_KEY" = "sk-change-me" ] && \
  echo "警告: LITELLM_MASTER_KEY 还是默认值，其他容器都能猜到" >&2

exec ./.venv/bin/litellm \
  --config ./config.yaml \
  --host 0.0.0.0 \
  --port "${LITELLM_PORT:-4000}"
