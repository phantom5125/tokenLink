# Tokenizer comparison beta

This feature is a manually triggered diagnostic for a configured API account.
It does not run at launch, on refresh, or on a schedule. The selected account's
explicit Keychain API key is read only after **Run comparison** is pressed.
Codex CLI and Claude Code OAuth credentials are excluded.

## Measurement

The app sends the same 30 fixed public texts to one official provider inference
endpoint, with a maximum of one output token per request. It reads only the
provider's input/prompt token count from each response and discards response
text. Missing, zero, or unusable counts are missing evidence. Authentication,
rate-limit, or other HTTP failures stop the run instead of producing a score.
The model ID is editable because availability depends on the account and may
change after this release.

The requests can consume a coding plan allowance or incur pay-as-you-go charges.
No measurement is persisted or exported in diagnostics. The fixed prompt texts
are bundled with the app and are unrelated to local transcripts or user data.

## Reference data and interpretation

`Sources/TokenLinkProviders/Resources/tokenizer-fingerprints.json` contains ten
OpenRouter-observed reference profiles from Bo Chen's MIT-licensed
[which-llm dataset](https://github.com/ictchenbo/which-llm), commit
`7907ca4baa553c0b2ef00e18df1403753833b909`, sampled on 2026-08-29/30.
Each profile records its source artifact path and collection timestamp. The
bundled corpus preserves the original test order; no reference API calls are
made when a user runs the feature.

For each reference profile, the app subtracts the observed count from the
reference count for every valid text. The most frequent difference is the
fixed offset; the score is the fraction of valid differences equal to that
offset. It requires at least 20 valid observations, 80% coverage, and five
distinct observed counts. Results are ranked as **closest reference
profiles**, with the raw counts and differences available for inspection.

The method is adapted from the [published study](https://arxiv.org/abs/2608.29930).
Its holdout evaluation found that token-count consistency can indicate a
shared tokenization and request-wrapping stack, but does not reliably establish
named model-family lineage. Tokenizer versions, chat templates, hidden prompts,
routing, caching, and provider usage accounting can change a profile. A gateway
can also rewrite usage metadata. This beta deliberately has no calibrated
identity threshold or "verified model" verdict.

## Current endpoints

| Provider | Fixed official endpoint | Response count |
| --- | --- | --- |
| Kimi | `api.kimi.com/coding/v1/messages` | `usage.input_tokens` |
| MiniMax | Global/China Anthropic-compatible Messages endpoint | `usage.input_tokens` |
| GLM | Global/China Chat Completions endpoint | `usage.prompt_tokens` |
| OpenRouter | Chat Completions endpoint | `usage.prompt_tokens` |
| DeepSeek | Chat Completions endpoint | `usage.prompt_tokens` |

All URLs are fixed by provider and region, require HTTPS, and pass the existing
exact-host and no-redirect transport policy. A balance-only key may be rejected
by the inference endpoint; that error is shown without the response body.
