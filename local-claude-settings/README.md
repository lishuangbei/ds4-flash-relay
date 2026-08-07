# local-claude-settings

在容器/开发机上把 Claude Code 接到本地 ds4-flash-0731 的启动配置。

## 用法

```bash
cp .env.local.example .env.local && $EDITOR .env.local   # 填 LITELLM_MASTER_KEY
./claude-ds4.sh                                          # 跟平时 claude 一样，参数透传
```

`.claude/settings.json` 只放**永不变化的量**：模型钉选（含 `model` 和全部 tier env）。
这是刻意收窄的——新版 Claude Code 里 settings.json 的 env 块会**覆盖** shell 导出的
同名变量（文件赢），所以任何可能通过 `.env.local` 调整的量（网关地址、compact 阈值）
都不能出现在这里，否则覆盖会被静默顶掉。另外 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
这类应用级变量放 env 块对 Claude Code 自身无效（issue #63186，截至 v2.1.224 未修），
只有启动脚本的 shell 导出可靠。

注意 `.claude/` 是**项目级**配置，只对"在这个目录里启动"的会话生效。要让它作用于
你的工作项目，把 `.claude/` 拷进各项目根目录；而启动脚本从任何目录跑都全量生效，
是权威路径。

## 脚本做了什么

- 启动前探活网关的 `/v1/messages`（Claude Code 实际要用的端点），失败带原因退出
- `unset ANTHROPIC_API_KEY`，防止 shell 里残留的真 key 把请求劫去 Anthropic
- 三个 model tier + subagent 全部钉死到 `deepseek-v4-flash`，不自动检测
  （`/v1/models` 的 `data[0]` 顺序无保证，自动选型会随机切到别的模型）
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW=100000`：Claude Code 对未知模型名默认假设
  200K 上下文，不管会一路推到本地模型的墙上（`exceed_context_size_error`）。
  这个变量直接重定义它眼中的总窗口（下限 100000，更低被静默夹回）；压缩在
  窗口−33K（硬编码 buffer）= 67K 触发。当前约定：Claude 窗口 100K +
  ds4-server `--ctx 112640`（110K）——服务端高出的 12.6K 用于吸收单轮突刺
  和两边分词器的计数差异，不要把服务端降到和窗口相等。

## 密钥

`DS4_GATEWAY_KEY` 只从 gitignored 的 `.env.local` 或环境变量读取，不进 git。
