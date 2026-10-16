---
name: ai
description: Working on the MetroMitra assistant — intents, lexicons, slot extraction, answer templates, the AiGateway abstraction or the online AI proxy. Use for any change in metro_core/assistant, metro_core/ai, features/assistant or the proxy.
---

# Assistant & AI

Spec: docs/ai.md.

## Non-negotiables
- Handlers return `Answer(templateId, facts, actions)`; never free text. Missing fact → `Answer.missing`.
- Template text lives in ARB (en + hi); facts are interpolated, never paraphrased.
- Station resolution only through `SearchIndex.resolve` with min score; ambiguity → clarify chips.
- Offline + unsupported → exactly "Connect to internet for an AI answer." (localized).
- The app never calls an LLM vendor directly; only `ProxyAiGateway` → our proxy. No keys in the app.
- AI answers are labelled, post-checked (unknown station names → reject), and cannot trigger actions.

## Adding an intent
1. Add utterances (en, hi, Hinglish; ≥ 10 each) to `test/assistant_cases.yaml` first.
2. Lexicon entries in `metro_core/assistant/lexicon/`.
3. Handler using existing services (Router, FareEngine, StationQuery) — no new data access paths.
4. Templates in both ARBs.
5. Add anti-fabrication cases (missing data, unknown entity).
6. `dart test packages/metro_core -t assistant`.

## Changing the AI model/provider
Server config in the proxy only; no app change. Keep the system prompt grounded-only.
