# Assistant & AI architecture

## Principle
The app is useful with **no LLM**. Common metro questions are answered by deterministic
code over verified local data. An online LLM is an optional fallback for questions the
dataset can't answer — and it is grounded and labelled.

```
User text
  ↓ normalize (search.md normalizer, Hinglish lexicon)
Intent detection (rules + keyword lexicons, en/hi/Hinglish)
  ↓ slot extraction (SearchIndex.resolve for stations; line names; time words; facility types)
Handler → metro_core services (Router, FareEngine, StationQuery, Nearby)
  ↓
Answer { templateId, facts[], actions[], confidence }  → localized template render
  ↓ (only if intent=unknown/unsupported AND online AI enabled AND network)
AiGateway.ask(question, groundingFacts) → labelled AI answer
```

## Intents (V1)
| Intent | Example (en / Hinglish / hi) | Slots | Service |
|---|---|---|---|
| route | "How do I reach Hauz Khas from Saket" / "Saket se Hauz Khas kaise jaun" | from?, to | Router (from defaults to nearest or asks) |
| nearest_station | "nearest metro" / "paas mein metro" | location | Nearby |
| gate_exit | "which gate for <landmark> at <station>" | station, landmark? | gate_landmark |
| platform | "which platform for <dir> at <station>" | station, destination/line | platform + direction |
| fare | "fare from A to B" / "kiraya kitna" | from, to, media? | FareEngine |
| first_last | "last metro from A" / "aakhri metro" | station, direction/to? | timing |
| interchange | "where do I change for B" | from, to | Router legs |
| facilities | "is there a toilet at A" | station, facility? | facility |
| accessibility | "lift at A" | station | accessibility, gates |
| parking | "parking at A" | station, vehicle? | parking |
| line_info | "Magenta line stations" | line | services |
| unknown | anything else | — | fallback |

Detection: ordered rules (regex + lexicon scores), highest score wins; ties or missing
required slots → **clarifying question with chips** (e.g. two stations match "Sector 18").
Lexicons live in `metro_core/assistant/lexicon/*.yaml` (language data, not metro data).

## No-fabrication guarantee (structural, not just tested)
- Handlers return `Answer` objects whose text is a **localized template** + `facts`
  (typed values pulled from the snapshot with provenance). The renderer only interpolates facts.
- A handler cannot emit free text. If a required fact is missing → `Answer.missing(...)`
  ("I don't have verified gate data for <station> yet").
- Every answer shows source line: dataset version + `verified_on`/confidence.
- Unknown station names never fall through to fuzzy guessing below the min score.

## Online AI (optional, opt-in setting, default ON only when online and question unsupported)
### Abstraction
```dart
abstract interface class AiGateway {           // metro_core/ai (pure Dart)
  Future<AiResult> ask(AiRequest request);     // AiResult = answer | refused | unavailable
}
class AiRequest { String question; String locale; List<Fact> grounding; String datasetVersion; }
```
Implementations (app/shared/data): `OfflineAiGateway` (always `unavailable`),
`ProxyAiGateway` (HTTPS to **our** proxy). The app never talks to an LLM vendor directly.

### Proxy (sync.md hosting)
- Holds vendor API keys server-side; model choice is server config → provider/model can change
  without an app release. Default: a small, cheap model (e.g. Claude Haiku 4.5 `claude-haiku-4-5-20251001`).
- System prompt: answer only metro facts present in `grounding`; for anything else give
  general guidance and say it may be wrong; never invent stations/fares/times/gates.
- Grounding: app sends only relevant facts (stations mentioned, nearby line info), not the whole DB.
- Post-check on device: any station name in the AI answer not in the dataset → answer
  rejected with "Couldn't verify this answer".
- Abuse/cost: per-install anonymous token, rate limit (e.g. 20/day), input length cap,
  optional Play Integrity later.
- Privacy: no location sent unless the question needs it and the user confirms.

### Offline + unsupported
Exactly: **"Connect to internet for an AI answer."** plus a hint of what can be asked offline.

## On-device model evaluation
| Option | Verdict V1 | Reason |
|---|---|---|
| Small on-device LLM (e.g. Gemma-class ~270M–1B via MediaPipe/LiteRT) | **No** | +150–600 MB, slow on low-end phones, hallucination risk, rules already cover the intent set |
| Gemini Nano via Android AICore | **No** | Limited device coverage; adds a vendor path |
| Tiny intent classifier (fastText/TFLite, < 2 MB) | **Maybe V1.x** | Only if logged (opt-in, anonymized) unknown-intent rate > 10 %. Classifier picks intent; slots/answers stay deterministic |

## Tests
Corpus `test/assistant_cases.yaml` (≥ 150 utterances en/hi/Hinglish) → expected intent + slots +
answer template; fabrication suite (nonexistent stations, missing gate data, impossible fares)
must yield `missing`/`unknown`, never a value.

## Implemented in M9 (offline assistant, ADR-061)
- Code: `packages/metro_core/lib/src/assistant/{lexicon,assistant_models,assistant}.dart`; app `features/assistant/*`
  (Ask tab: suggestions, answer cards with source line and actions, clarify chips, station picker for missing slots).
- Intents: all 12 of the table above. `nearest_station` hands over to Nearby (the assistant never reads location).
- Tests: `packages/metro_core/test/assistant_cases.yaml` (190 utterances: en 91 / Hinglish 51 / Hindi 48, on the TEST
  fixture), `assistant_test.dart` (anti-fabrication: ids exist, non-answers carry no values, values equal engine/data,
  NULL never "no", nonexistent places, empty data, day types, unreachable pairs, clarification, determinism, fuzz,
  p50 < 20 ms on the fixture), app `assistant_test.dart` (screen flows, every template renders in en + hi).
- Real draft (local check only): p50 18 ms, p95 ~180 ms (route questions = the M3 planner). Most real answers are
  "missing" today because the draft has no gates, platforms, timings, facilities or fares; "HUDA City Centre" is not an
  alias in the draft, so it is "not found".
- Not in M9: AiGateway / proxy / online answers (M11), lexicon files outside code, voice input.

## Implemented in M11 (online AI fallback, ADR-063)
- Core (pure Dart): `metro_core/src/ai/ai_gateway.dart` - `AiGateway` (+ `OfflineAiGateway`), `AiRequest/AiResult` (answer / refused / unavailable), `AiGrounding.build` (facts about the stations the question names, from the dataset only), `AiPostCheck`.
- App: `shared/data/ai/proxy_ai_gateway.dart` (https only, 12 s timeout, answers capped, anonymous random per-run token, only question + locale + dataset facts + dataset version are sent - never a position), `features/assistant/application/ai_providers.dart` (`METROMITRA_AI_URL`, empty = no online AI; `onlineAiEnabledProvider`, default on, persisted by Settings in M12), Ask tab `ai-<i>` card.
- When: only if the offline assistant answered `unknown`, a gateway is configured and the user allows it. The offline answer is always shown first and never replaced; the AI card is labelled "AI-generated - general guidance, not verified metro data". Offline shows exactly "Connect to internet for an AI answer." (only when a gateway is configured).
- Post-check on device: every `[[Station]]` the model marks must be a station/alias/code in the dataset; unmarked "X Station" names too; any amount or clock time must appear in the grounding; empty/over-long text is refused ("Couldn't verify this answer.").
- Proxy: `server/ai-proxy` (Dart, `bin/server.dart`): `POST /v1/ask`, body/size validation, 20/day per token and per address + burst limit, provider abstraction (`LlmProvider`; `AnthropicProvider`, model from `AI_MODEL`, default `claude-haiku-4-5-20251001`), key only from `AI_API_KEY`, no question logging, plain-text answers. Deploy behind TLS; the container/host choice is the owner's.
- Not done: Play Integrity, persistent per-install token (needs the M12 settings store), streaming, the Settings toggle UI (M12). No real proxy is deployed and no key exists; everything is tested against loopback fakes.
