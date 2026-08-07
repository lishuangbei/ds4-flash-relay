#!/usr/bin/env bash
# Install the LiteLLM proxy and everything it needs. Run once; safe to re-run.
# Targets Debian/Ubuntu (apt); works on macOS if python3/curl already present.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

APT=""
if command -v apt-get >/dev/null; then
  if [ "$(id -u)" = 0 ]; then APT="apt-get"
  elif command -v sudo >/dev/null; then APT="sudo apt-get"
  fi
fi

echo "==> [1/5] 系统依赖"
need=""
command -v python3 >/dev/null                     || need="$need python3"
python3 -c 'import ensurepip' 2>/dev/null         || need="$need python3-venv"
python3 -m pip --version >/dev/null 2>&1          || need="$need python3-pip"
command -v curl >/dev/null                        || need="$need curl"
if [ -n "$need" ]; then
  [ -n "$APT" ] || { echo "缺:${need}，且没有 apt-get/sudo —— 请手动安装后重跑" >&2; exit 1; }
  $APT update
  $APT install -y $need ca-certificates
fi
echo "    ok"

echo "==> [2/5] venv"
[ -d .venv ] || python3 -m venv .venv
./.venv/bin/pip install -q --upgrade pip setuptools wheel

echo "==> [3/5] litellm[proxy]"
# 'proxy' extras 提供 proxy_server（漏掉它就是
# "ModuleNotFoundError: No module named 'proxy_server'"）。
# fastapi 钉死在 0.140.3：0.140.4+ 移除了 get_flat_dependant，而 litellm
# （实测至 1.95.0）还在导入它，其依赖声明 (<1.0) 拦不住，装最新必炸
# "ImportError: cannot import name 'get_flat_dependant'"。
# litellm 上游适配新 fastapi 后可改回不钉版本。
./.venv/bin/pip install --upgrade 'litellm[proxy]' 'fastapi==0.140.3'

echo "==> [4/5] 自检（当场暴露缺件，而不是等 start.sh 才炸）"
./.venv/bin/python - <<'PY'
import litellm.proxy.proxy_server  # noqa: F401  ← 正是报错缺的模块
import uvicorn, fastapi, yaml      # noqa: F401
from importlib.metadata import version
print(f"    litellm {version('litellm')}  fastapi {version('fastapi')}  uvicorn {version('uvicorn')}")
PY
./.venv/bin/litellm --version >/dev/null
echo "    litellm CLI ok"

echo "==> [5/5] .env"
[ -f .env ] || { cp .env.example .env; echo "    已生成 .env —— 改完再启动"; }

echo
echo "装好了。接下来："
echo "  1. 编辑 .env（Mac 地址、master key）"
echo "  2. ./healthcheck.sh    确认上游通"
echo "  3. ./start.sh          起网关"
