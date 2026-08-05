#!/usr/bin/env bash
# Install the LiteLLM proxy. Run once. Targets Debian/Ubuntu.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "==> 依赖"
if ! command -v python3 >/dev/null; then
  apt-get update && apt-get install -y python3 python3-pip python3-venv curl
fi
command -v curl >/dev/null || apt-get install -y curl

echo "==> venv + litellm"
python3 -m venv .venv
./.venv/bin/pip install --upgrade pip
./.venv/bin/pip install 'litellm[proxy]'

echo "==> .env"
[ -f .env ] || { cp .env.example .env; echo "    已生成 .env —— 改完再启动"; }

echo
echo "装好了。接下来："
echo "  1. 编辑 .env（Mac 地址、qwen 地址、master key）"
echo "  2. ./healthcheck.sh    确认上游通"
echo "  3. ./start.sh          起网关"
