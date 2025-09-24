# System Flow Playbook

## 1. System Snapshot
- Architecture: Mobile Web client + n8n orchestration + MySQL data stack; Symanto analysis APIs and the OpenAI Responses API as external services.
- Core modules (A–I): Normalization (A), Bayesian fusion (B), Confidence/Quality (C), Time-series features (D), Intervention planner (E), LLM post‑processing (F), KPI analytics (G), Data invariants (H), Reliability controls (I). n8n flows and UI wire everything together.

## 2. End-to-End Journeys
### 2.1 Onboarding → Baseline
1. Scoring & normalization (A): Score IPIP‑NEO‑120, convert to T‑scores (50±10) and 0–1, attach `norm_version` and `scale_type`; validate inputs and handle missingness.
2. Persistence (H): Append to `baseline_profiles`; enforce `scale_type ∈ {T,p01}`, T∈[0,100], p01∈[0,1] with CHECK/roles/triggers.
3. Prior (B): Baseline serves as the Bayesian prior for later updates.

### 2.2 Daily Measurement Pipeline
1. Chat → analysis: Language detect/translate, call Symanto Big5/CS/PT/Sentiment/Aspect; normalize to 0–1/T in (A).
2. Quality (C): Estimate per‑trait observation variance σx² and quality flags from tokens, MT‑QE, OOD, language mismatch; apply lower bounds and smoothing.
3. Bayesian fusion (B): Combine prior and likelihood with precision weights (1/variance), append posterior (T and 0–1) and variance to `ocean_timeseries`.
4. Features (D): Compute EWMA, recent slope, rolling variance, and optional change‑points (CUSUM/PH/BOCPD); feed dashboard and planner (E).

### 2.3 Intervention & Engagement
1. Planning (E): Use posterior + variance, confidence/flags, EWMA/slope/variance, CS/PT, Sentiment/Aspect to choose CBT/WOOP/If‑Then with tone/length/CTA per JITAI; clip strength under low confidence/high variance.
2. Generation & safety (F): Generate via OpenAI Responses; enforce Structured Outputs (JSON Schema), moderation and XSS sanitization, length/format normalization, staged fallbacks, full audit logging.
3. Logging & analytics (G/H): Record delivery and user actions as idempotent events (`behavior_events`); compute KPI (execution rate/streak/retention, A/B + CUPED, EWMA trends). H enforces append‑only/uniqueness/roles.
4. Reliability (I): Wrap external calls (Symanto/OpenAI/notifications) with Retry‑After–aware exponential backoff + jitter, circuit breakers, token buckets, and idempotency keys.

## 3. Module Cheat Sheet (Brief)
- A: Normalize IPIP/Symanto; keep dual units T and p01; validate/handle missingness.
- B: Precision‑weighted prior×likelihood; persist posterior μ/σ² in T and 0–1 with variance caps.
- C: Estimate σx² and quality gates from tokens/QE/OOD/language; calibrate (e.g., temperature) if applicable.
- D: EWMA/slope/variance + optional change‑points; guide dashboards and E’s intensity.
- E: JITAI planner (rules → bandits); control tone/length/CTA; log rationale.
- F: Structured Outputs/Moderation/XSS/fallbacks/audit for LLM output.
- G: KPI (execution rate CI, streak, retention, effect sizes, CUPED, EWMA).
- H: Data invariants (range CHECKs, append‑only, UNIQUE, roles/views/triggers, audit).
- I: Retries/rate‑limits/circuits/idempotency (429/5xx/timeout; honor Retry‑After).

## 4. References
- Specs: `docs/specification/algorism/*` (modules A–I)
- Diagrams: `docs/diagrams/` (Mermaid split diagrams)

