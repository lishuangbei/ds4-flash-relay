#!/usr/bin/env bash
# Install the LiteLLM proxy and everything it needs. Run once; safe to re-run.
# Targets Debian/Ubuntu (apt); works on macOS if python3/curl already present.
#
# 用法：
#   ./install.sh              装 PyPI 上当前最新的 litellm（默认）
#   ./install.sh 1.106.12     装指定版本；升级、降级、回退都用这个
#   LITELLM_VERSION=1.106.12 ./install.sh    同上，参数优先于环境变量
#
# 重跑只换 .venv 里的库，正在运行的网关要重启（停掉再 ./start.sh）才会用上新版本。
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

WANT="${1:-${LITELLM_VERSION:-latest}}"
case "$WANT" in
  latest) ;;
  -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)
    if ! [[ "$WANT" =~ ^[0-9]+(\.[0-9]+)+([a-z0-9.]+)?$ ]]; then
      echo "版本号格式不对: '$WANT'（例: 1.106.12；不带参数则装最新）" >&2; exit 1
    fi
    # PyPI 上被投毒过的版本（2026-03 与 2026-10，均已下架），写错也不放行。
    case "$WANT" in
      1.82.7|1.82.8|1.107.0) echo "litellm $WANT 是已知的恶意版本，拒绝安装" >&2; exit 1 ;;
    esac ;;
esac

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
# 记下升级前的版本，装完后给出回退命令
PREV="$(./.venv/bin/python -c 'from importlib.metadata import version; print(version("litellm"))' 2>/dev/null || true)"

echo "==> [3/5] litellm[proxy]"
# 'proxy' extras 提供 proxy_server（漏掉它就是
# "ModuleNotFoundError: No module named 'proxy_server'"）。
# fastapi 钉死在 0.140.3：0.140.4+ 移除了 get_flat_dependant，而 litellm
# （实测至 1.95.0）还在导入它，其依赖声明 (<1.0) 拦不住，装最新必炸
# "ImportError: cannot import name 'get_flat_dependant'"。
# 这个钉法对新旧版本都能用（实测 litellm 1.97.0 与 1.111.0 都能起网关），
# 所以指定旧版本回退时不用另外处理。
if [ "$WANT" = latest ]; then
  echo "    目标: 最新版${PREV:+（当前 ${PREV}）}"
  ./.venv/bin/pip install --upgrade 'litellm[proxy]' 'fastapi==0.140.3'
else
  echo "    目标: $WANT${PREV:+（当前 ${PREV}）}"
  ./.venv/bin/pip install "litellm[proxy]==$WANT" 'fastapi==0.140.3'
fi

echo "==> [4/5] 自检（当场暴露缺件，而不是等 start.sh 才炸）"
./.venv/bin/python - <<'PY'
import litellm.proxy.proxy_server  # noqa: F401  ← 正是报错缺的模块
import uvicorn, fastapi, yaml      # noqa: F401
from importlib.metadata import version
print(f"    litellm {version('litellm')}  fastapi {version('fastapi')}  uvicorn {version('uvicorn')}")
PY
./.venv/bin/litellm --version >/dev/null
echo "    litellm CLI ok"
NOW="$(./.venv/bin/python -c 'from importlib.metadata import version; print(version("litellm"))')"
if [ "$WANT" != latest ] && [ "$NOW" != "$WANT" ]; then
  echo "装上的是 ${NOW}，不是要求的 $WANT" >&2; exit 1
fi

echo "==> [5/5] .env"
[ -f .env ] || { cp .env.example .env; echo "    已生成 .env —— 改完再启动"; }

echo
if [ -n "$PREV" ] && [ "$PREV" != "$NOW" ]; then
  echo "litellm $PREV -> ${NOW}。正在运行的网关要重启才生效；"
  echo "回退: ./install.sh $PREV  然后重启网关。"
  echo
fi
echo "装好了（litellm ${NOW}）。接下来："
echo "  1. 编辑 .env（Mac 地址、master key）"
echo "  2. ./healthcheck.sh    确认上游通"
echo "  3. ./start.sh          起网关"
