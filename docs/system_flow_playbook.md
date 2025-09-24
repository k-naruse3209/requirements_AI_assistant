# System Flow Playbook / システムフロープレイブック

## 1. System Snapshot / システム全景
- The AI coach spans a mobile web client, n8n orchestration, and a MySQL data stack, backed by Symanto analysis APIs and the OpenAI Responses API for interventions.【F:README.md†L23-L34】【F:README.md†L36-L39】
- Internal logic is organized into nine must-own modules (A–I) that cover normalization, Bayesian fusion, confidence heuristics, drift features, intervention planning, LLM post-processing, KPI analytics, data invariants, and reliability controls; supporting blocks (J–N) wire n8n flows, UI, and third-party services.【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L1-L58】

## 2. End-to-End Journeys / エンドツーエンドの流れ
### 2.1 Onboarding → Baseline / オンボーディングと基準値
1. User completes the IPIP-NEO-120 questionnaire in the client; module A scores responses, converts them to T-scores (50±10) and 0–1 scale, tags norm versions, and validates inputs.【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L2-L4】
2. Baseline records are stored append-only via module H, ensuring `scale_type ∈ {T, p01}` and value ranges, with MySQL constraints and triggers preventing mutation.【F:docs/specification/algorism/H. データモデルと不変条件の実装†L22-L83】
3. These priors become the reference for Bayesian updates and dashboarding in later flows.【F:docs/specification/algorism/B. ベイズ統合†L7-L17】

### 2.2 Daily Measurement Pipeline / 日次測定パイプライン
1. User chat text arrives; module A re-applies normalization to Symanto outputs so they share the same 0–1/T dual scales as onboarding scores.【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L2-L6】
2. Module C evaluates observation quality: token length, translation route, calibration metrics, and OOD signals drive per-trait variance estimates and quality flags that later weight the Bayesian fusion.【F:docs/specification/algorism/C. 確信度推定と品質ルール†L3-L115】
3. Module B combines priors and daily likelihoods with precision-weighted averaging, bounding variances, logging meta-data, and persisting posteriors in `ocean_timeseries` with both human and machine scales.【F:docs/specification/algorism/B. ベイズ統合†L3-L83】
4. Module D computes EWMA, short-window slope, rolling variance, and optional change-point flags, feeding dashboards and the intervention planner with fresh trend context.【F:docs/specification/algorism/D. ドリフトとトレンド検知の時系列特徴量†L1-L115】

### 2.3 Intervention & Engagement Loop / 介入とエンゲージメント
1. Module E ingests the posterior snapshot, confidence flags, drift metrics, and Symanto features (Communication Style, Personality Traits, Sentiment, Aspect) to select CBT/WOOP/If–Then tactics with tone and length constraints aligned to JITAI principles.【F:docs/specification/algorism/E. 介入プランナー（JITAIの中核）†L7-L133】【F:docs/specification/symantoAPI/HowToUse†L3-L26】
2. The planner emits structured prompts plus rationale tags for the OpenAI Responses API; module F enforces schema-compliant JSON, moderation, sanitization, tone/length normalization, multi-stage fallbacks, and full audit trails before delivery.【F:docs/specification/algorism/F. LLM出力の後処理（Post-processing）†L1-L133】
3. Delivered cards, user actions, and rationale metadata are logged for KPI aggregation (module G) and for replay safety through idempotent event tables guarded by module H.【F:docs/specification/algorism/G. KPI集計と評価†L3-L86】【F:docs/specification/algorism/H. データモデルと不変条件の実装†L24-L125】
4. Module I wraps every external call (Symanto, OpenAI, notifications) with retry budgets, exponential backoff with jitter, circuit breakers, token-bucket throttling, and idempotency keys, keeping the overall loop resilient.【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L1-L103】

## 3. Module Cheat Sheet / モジュール早見表
| Module | Purpose | Key Inputs | Key Outputs | Guardrails |
| --- | --- | --- | --- | --- |
| A | Normalize IPIP & Symanto scores, enforce scale metadata | Raw questionnaire answers, Symanto scores | Dual-scale OCEAN vectors, norm metadata | Input validation, missing-value handling |【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L2-L6】
| B | Bayesian fusion of priors and daily likelihoods | Prior/variance, observation/variance, meta | Posterior μ/σ² in T & 0–1, logs | Variance caps, deterministic updates |【F:docs/specification/algorism/B. ベイズ統合†L3-L108】
| C | Confidence & quality gating | Normalized observations, meta (tokens, QE, OOD) | Per-trait variances, confidence, flags | Token/QE thresholds, calibration checks |【F:docs/specification/algorism/C. 確信度推定と品質ルール†L3-L123】
| D | Drift features for dashboards & planning | Posterior time series, λ, window sizes | EWMA, slope, rolling variance, flags | SPC thresholds, optional change detection |【F:docs/specification/algorism/D. ドリフトとトレンド検知の時系列特徴量†L1-L129】
| E | Just-in-time intervention planner | OCEAN_hat, variance, flags, CS/PT, sentiment, trends | Technique, tone, length, CTA, LLM prompt, rationale | Safety clips on low confidence, bandit upgrade path |【F:docs/specification/algorism/E. 介入プランナー（JITAIの中核）†L3-L147】
| F | LLM post-processing & safety | Planner prompt outputs, raw LLM JSON | Validated card payload, sanitized text, audit bundle | Structured Outputs, moderation, DOMPurify, fallbacks |【F:docs/specification/algorism/F. LLM出力の後処理（Post-processing）†L1-L134】
| G | KPI aggregation & experimentation | Behavior events, planner metadata, trends | Execution rate, retention, streaks, A/B metrics | Wilson CI, CUPED, anti-peeking procedures |【F:docs/specification/algorism/G. KPI集計と評価†L3-L95】
| H | Data invariants & persistence | Module outputs, retry metadata | Append-only stores, audit logs, roles | CHECK/FK/UNIQUE, triggers, GDPR minimization |【F:docs/specification/algorism/H. データモデルと不変条件の実装†L1-L140】
| I | Reliability shell | HTTP requests to external/internal APIs | Retry-wrapped responses, throttle decisions | Retry taxonomy, jittered backoff, circuit breakers |【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L1-L103】

## 4. Data Lifecycle Controls / データライフサイクル管理
- Baseline (`baseline_profiles`) and posterior series (`ocean_timeseries`) enforce scale bounds, append-only semantics, and role-separated access; triggers raise SQLSTATE 45000 on mutation attempts.【F:docs/specification/algorism/H. データモデルと不変条件の実装†L24-L105】
- Behavior events use `idempotency_key` to neutralize retries while module I’s policies ensure duplicate API calls replay safely.【F:docs/specification/algorism/H. データモデルと不変条件の実装†L84-L125】【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L40-L103】
- Audit logging captures every hop from inputs to delivered cards for at least 30 days, aligning with OWASP secure logging and GDPR minimization rules.【F:docs/specification/algorism/H. データモデルと不変条件の実装†L35-L140】

## 5. Analytics & Feedback Loop / 分析とフィードバック
- Execution, streak, retention, and effect-size metrics are recomputed on daily/weekly cadences with Wilson intervals and CUPED adjustments, surfacing EWMA trends to the planner and stakeholders.【F:docs/specification/algorism/G. KPI集計と評価†L27-L86】
- Planner upgrades (LinUCB/Thompson) use these rewards plus logged rationale tags, enabling safe exploration when confidence and posterior variance permit.【F:docs/specification/algorism/E. 介入プランナー（JITAIの中核）†L67-L133】【F:docs/specification/algorism/G. KPI集計と評価†L41-L86】

## 6. External Service Strategy / 外部サービス活用戦略
- Symanto endpoints supply Big Five measurements plus Communication Style, Personality Traits, Sentiment, and Aspect signals that steer tone and tactic selection; Sentiment/Emotion/Aspect also drive micro-intervention triggers.【F:docs/specification/symantoAPI/HowToUse†L3-L26】
- OpenAI Responses API generates structured cards under module F’s schema guardrails, with moderation and sanitization closing OWASP LLM02 gaps.【F:docs/specification/algorism/F. LLM出力の後処理（Post-processing）†L1-L133】

## 7. Reliability Playbook / 信頼性プレイブック
- Retry budgets follow Google/AWS guidance: retry only transient classes (408/429/5xx/timeouts), honor `Retry-After`, add jitter, and cap attempts at three; circuit breakers and token buckets prevent thundering herds.【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L23-L103】
- n8n workflow nodes enable “Retry on Fail” and wait steps, but hardened HTTP clients still enforce idempotency keys and backoff logic server-side.【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L93-L103】

## 8. Implementation Roadmap / 実装ロードマップ
1. Ship normalization (A), Bayesian fusion (B), and confidence heuristics (C) together—they are mutually dependent and unblock the measurement pipeline.【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L40-L45】
2. Add drift analytics (D) and KPI aggregation (G) to make the posterior stream observable and to unlock planner telemetry.【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L40-L43】
3. Deliver the rule-based planner (E) plus LLM hardening (F); once stable, graduate to contextual bandits with the KPI feedback loop.【F:docs/specification/algorism/E. 介入プランナー（JITAIの中核）†L32-L147】【F:docs/specification/algorism/F. LLM出力の後処理（Post-processing）†L1-L133】
4. Lock down data invariants (H) and the reliability layer (I) so retried workflows and analytics stay trustworthy in production.【F:docs/specification/algorism/H. データモデルと不変条件の実装†L1-L140】【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L1-L103】

## 9. Quick Reference Timeline / 時系列サマリ
| Phase | Trigger | Outputs | Observability |
| --- | --- | --- | --- |
| Baseline Week | Complete IPIP-NEO-120 | `baseline_profiles`, priors cached | MySQL constraints, audit log entries |【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L2-L4】【F:docs/specification/algorism/H. データモデルと不変条件の実装†L24-L83】
| Daily Check-in | Chat submission processed | Posterior + drift metrics | EWMA/slope dashboards, quality flags |【F:docs/specification/algorism/C. 確信度推定と品質ルール†L3-L115】【F:docs/specification/algorism/D. ドリフトとトレンド検知の時系列特徴量†L1-L115】
| Intervention Delivery | Planner decision executed | Structured card, rationale tags | Moderation logs, KPI events |【F:docs/specification/algorism/E. 介入プランナー（JITAIの中核）†L7-L125】【F:docs/specification/algorism/F. LLM出力の後処理（Post-processing）†L28-L120】【F:docs/specification/algorism/G. KPI集計と評価†L3-L86】
| Reliability Loop | API request hits limits/failures | Retry scheduling, token bucket state | Retry logs, circuit breaker status |【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L1-L103】

