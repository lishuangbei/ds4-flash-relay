# local-claude-settings

在容器/开发机上把 Claude Code 接到本地 ds4-flash-0731 的启动配置。

## 用法

```bash
cp .env.local.example .env.local && $EDITOR .env.local   # 填 LITELLM_MASTER_KEY
./claude-ds4.sh                                          # 跟平时 claude 一样，参数透传
```

`.claude/` 放 Claude Code 的项目级配置（settings.json 等），随仓库分发。

## 脚本做了什么

- 启动前探活网关的 `/v1/messages`（Claude Code 实际要用的端点），失败带原因退出
- `unset ANTHROPIC_API_KEY`，防止 shell 里残留的真 key 把请求劫去 Anthropic
- 三个 model tier + subagent 全部钉死到 `deepseek-v4-flash`，不自动检测
  （`/v1/models` 的 `data[0]` 顺序无保证，自动选型会随机切到别的模型）
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW=135000`：Claude Code 对未知模型名默认假设
  200K 上下文，不设阈值会一路推到本地模型的墙上（`exceed_context_size_error`）。
  取值 = ds4-server 的 `--ctx` 减 25-30K；两边要一起调。

## 密钥

`DS4_GATEWAY_KEY` 只从 gitignored 的 `.env.local` 或环境变量读取，不进 git。
