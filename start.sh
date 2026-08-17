#!/usr/bin/env bash
# 启动 LiteLLM 网关。其他容器打 http://local-llm:<port>/v1
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

[ -f .env ] || { echo "缺 .env —— 先 cp .env.example .env 并填好" >&2; exit 1; }
set -a; source .env; set +a

[ "$LITELLM_MASTER_KEY" = "sk-change-me" ] && \
  echo "警告: LITELLM_MASTER_KEY 还是默认值，其他容器都能猜到" >&2

# 上游走 tailnet；环境重启后 tailscale 常常没起来，先拉起再启动网关。
# 覆盖两种情况：tailscaled 守护进程没跑 / 跑了但接口没 up。
# 关掉可设 SKIP_TAILSCALE=1（比如上游改成了非 tailnet 地址时）。
ensure_tailscale() {
  [ "${SKIP_TAILSCALE:-0}" = "1" ] && return 0
  command -v tailscale >/dev/null || { echo "警告: 未装 tailscale，上游若走 tailnet 会连不通" >&2; return 0; }
  if tailscale status --peers=false >/dev/null 2>&1; then
    echo "tailscale 在线: $(tailscale ip -4 2>/dev/null | head -1)"
    return 0
  fi
  local SUDO=""
  [ "$(id -u)" != 0 ] && command -v sudo >/dev/null && SUDO="sudo"
  if ! pgrep -x tailscaled >/dev/null 2>&1; then
    echo "拉起 tailscaled ..."
    if command -v systemctl >/dev/null && $SUDO systemctl start tailscaled 2>/dev/null; then
      :
    else
      $SUDO sh -c 'nohup tailscaled >/var/tmp/tailscaled.log 2>&1 &'
      sleep 2
    fi
  fi
  echo "tailscale up ..."
  # 有存量状态时静默上线；状态丢了需要重新认证——超时失败并提示，不无限挂着
  if ! $SUDO tailscale up --timeout=30s; then
    echo "tailscale up 失败（可能需要重新认证）：手动跑 'sudo tailscale up' 完成登录后重试" >&2
    exit 1
  fi
  local n=0
  until tailscale ip -4 >/dev/null 2>&1 || [ $n -ge 15 ]; do sleep 1; n=$((n+1)); done
  tailscale ip -4 >/dev/null 2>&1 || { echo "tailscale 起了但拿不到地址，检查 'tailscale status'" >&2; exit 1; }
  echo "tailscale 在线: $(tailscale ip -4 | head -1)"
}
ensure_tailscale

exec ./.venv/bin/litellm \
  --config ./config.yaml \
  --host 0.0.0.0 \
  --port "${LITELLM_PORT:-4000}"
