# local-claude-settings

在容器/开发机上把 Claude Code 接到本地 ds4-flash-0731 的启动配置。

## 用法

```bash
cp .env.local.example .env.local && $EDITOR .env.local   # 填 LITELLM_MASTER_KEY
./claude-ds4.sh                                          # 跟平时 claude 一样，参数透传
```

`.claude/settings.json` 是同一套配置的声明式副本（模型钉死 + compact 阈值 + 网关地址，
唯独不含密钥）——就算有人在这个目录里直接跑裸 `claude` 忘了走脚本，模型和阈值也是对的，
只会因为缺 key 在鉴权处大声失败，而不是静默打到真 Anthropic API 上。
注意旧版 Claude Code（约 v2.1.87 前后）有 settings.json env 块被忽略的已知 bug，
所以启动脚本的 export 仍是权威路径，settings.json 是兜底。

## 脚本做了什么

- 启动前探活网关的 `/v1/messages`（Claude Code 实际要用的端点），失败带原因退出
- `unset ANTHROPIC_API_KEY`，防止 shell 里残留的真 key 把请求劫去 Anthropic
- 三个 model tier + subagent 全部钉死到 `deepseek-v4-flash`，不自动检测
  （`/v1/models` 的 `data[0]` 顺序无保证，自动选型会随机切到别的模型）
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW=90000`：Claude Code 对未知模型名默认假设
  200K 上下文，不设阈值会一路推到本地模型的墙上（`exceed_context_size_error`）。
  当前约定：ds4-server `--ctx 112640`（110K）+ 阈值 90000（缓冲约 22K）。
  调服务端 ctx 时同步三处：`.env.local` 的 `DS4_COMPACT_WINDOW`、
  `.claude/settings.json`、Mac 侧 `config.sh` 的 `CTX`。

## 密钥

`DS4_GATEWAY_KEY` 只从 gitignored 的 `.env.local` 或环境变量读取，不进 git。
