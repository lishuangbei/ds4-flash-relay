# ds4-flash-relay

A LiteLLM gateway that puts [DeepSeek-V4-Flash-0731](https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-0731) — running locally on an Apple Silicon Mac via [antirez/ds4 (DwarfStar)](https://github.com/antirez/ds4) — behind a single OpenAI-compatible endpoint, so containers on another machine can use it.

```
your containers ──► relay:4000/v1 (LiteLLM) ─┬─► mac:8000/v1  ds4-flash-0731
                                             └─► local        qwen3.6 / whatever
```

Nothing here is specific to DeepSeek — any OpenAI-compatible upstream works. The value is in the three settings that are easy to get wrong when the upstream is a *local* model rather than a cloud API.

## Setup

```bash
./install.sh              # latest LiteLLM from PyPI
./install.sh 1.106.12     # or an exact version; also how you upgrade, downgrade or roll back
```

Re-running `install.sh` only replaces the library in `.venv`. It prints the version it replaced and the command to go back to it; restart the gateway (stop it, then `./start.sh`) for the change to take effect. `LITELLM_VERSION=1.106.12 ./install.sh` does the same as the argument. The default takes whatever PyPI published most recently, which may be hours old, so pin a version when you want to know in advance what you are getting.

```bash
cp .env.example .env && $EDITOR .env
```

```bash
./healthcheck.sh
```

```bash
./start.sh
```

## Calling it

```bash
curl http://relay:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "content-type: application/json" \
  -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"hi"}],"stream":true}'
```

Switch models by changing the `model` field. Application code doesn't change.

## healthcheck.sh

Probes four layers separately, because "it doesn't work" has four very different causes:

```
[1/4] network to upstream host
[2/4] ds4-server endpoint          GET /v1/models
[3/4] actual inference             POST /v1/chat/completions
[4/4] LiteLLM gateway              /health/liveliness
```

Step 3 can take tens of seconds on a cold prefix. That's expected — see below.

## The three settings that matter

**`timeout: 600` / `stream_timeout: 600`.** A local model's prefill is tens of seconds, not the sub-second time-to-first-token you get from a cloud API. LiteLLM's default timeout kills these requests. This is the single most common failure. Prefer `stream: true` on the client side.

**`max_parallel_requests`.** Match it to the upstream's actual concurrency (`--batched-session N` on ds4-server). Setting it here means excess requests queue at the gateway instead of piling up against a server that can't serve them.

**`master_key`.** ds4-server performs no authentication at all — the `api_key` it accepts is a placeholder it never validates. Anything that can reach its port can use it. Routing all clients through the gateway's `master_key` is what puts an auth layer back.

## Exposing ds4-server

ds4-server binds `127.0.0.1` by default and only speaks IPv4 (a single `AF_INET` socket — `0.0.0.0` will not expose it over IPv6).

Simplest, exposes it on every interface — LAN, VPN, tailnet:

```bash
ds4-server --host 0.0.0.0 --port 8000 -m model.gguf
```

Narrower, keeps ds4 on loopback and exposes only one interface:

```bash
socat TCP-LISTEN:8000,bind=<tailscale-ip>,fork,reuseaddr TCP:127.0.0.1:8000
```

The second is worth the extra step: the exposure is a separate process you can stop with Ctrl-C, without restarting a server that takes ~40s to load 90 GiB of weights.

## Notes

- **Thinking mode is on by default.** ds4-server defaults to DeepSeek's thinking mode, and with a small `max_tokens` the reply you see is truncated reasoning. Pass `"think": false` in the request body for direct answers — verified to pass through this gateway config (`drop_params` does not strip it).
- **KV cache is per-prefix.** Different applications with different system prompts don't share cached prefixes, so each pays its own cold start. ds4-server's `--kv-disk-dir` makes those prefixes survive restarts.
- **Model naming.** `hosted_vllm/<name>` and `openai/<name>` in `litellm_params.model` both select the OpenAI-compatible protocol; the part after the slash is what gets sent upstream as the model id.
- **Use `hosted_vllm/` for the DeepSeek route.** The TensorFold engine on the Spark puts streamed `usage` in the same chunk as `finish_reason` instead of a separate `choices: []` chunk. On the `openai/` path LiteLLM up to 1.100.x discards that usage and reports its own token estimate, so `prompt_tokens_details.cached_tokens` never reaches the client and cache hits always read as 0. LiteLLM 1.101.0 fixed that, but the `hosted_vllm/` path keeps the upstream usage and forwards `reasoning_effort` on old and new versions alike, so it stays the default and a rollback does not bring the problem back. With it, `/v1/messages` is translated to the upstream's `/v1/chat/completions`; `/v1/responses` is still forwarded as is.

## License

MIT
