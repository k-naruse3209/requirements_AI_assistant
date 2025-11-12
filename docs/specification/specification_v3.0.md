要件定義書（AIコーチ / v1.0）
1. 目的・背景
Big Five（OCEAN）に基づき、初回はIPIP-NEO-120でベースラインを確立し、以後は日々のチャット文から性格推定を更新、JITAI思想でCBT/WOOP/If–Thenのマイクロ介入を最適化して提示する。 JITAIの定義と設計原理は文献に準拠する。pmc.ncbi.nlm.nih.gov


技術中核はn8nワークフロー、MySQLデータ層、Symanto各API、LLMのResponses API。（全体像） / docs.n8n.io+2docs.n8n.io+2


2. スコープ
対象: 自己成長・行動変容支援（非医療）。日次チェックイン、週次レビュー、通知。


非スコープ（パイロット段階）: 厳格な医療SOP・PHI処理は最小限、将来拡張。


3. 利用者・関係者
エンドユーザー（Mobile Web）、オペレーター（運用・分析）、開発・ML/データ基盤、セキュリティ担当。


4. 主要ユースケース
オンボーディング: IPIP-NEO-120の120項目回答→Baseline保存→handoff（baseline_id, user_id）。


日次測定: チャット入力→言語判定/翻訳→Symanto Big Five→正規化→Prior（Baseline）と統合→OCEAN_hat/信頼度を時系列に保存→handoff。


介入: 同じ発話をCommunication Style/Personality Traits/Sentiment/Aspectで解析→PlannerでCBT/WOOP/If–Then選択→LLMで自然文カード→KPI記録・通知。


ダッシュボード: 行動実行率・継続日数・Tスコア推移・EWMA/傾き/分散の可視化。


5. 機能要件（FR）
FR1 Baseline: IPIP-NEO-120採点、OCEAN＋30ファセット＋信頼性を保存（T=50±10、必要に応じ百⽂位）。 IPIP-NEO-120のスコアキー/規範は公式に準拠。ipip.ori.org+2ipip.ori.org+2


FR2 日次テキスト推定: Symanto Big Fiveに発話を送信しOCEANとconfidenceを取得、0–1/Tに正規化、しきい値・確度に応じ段階反映。 / Symanto - Psychology AI+3RapidAPI+3RapidAPI+3


FR3 介入（Planner）: Communication Style/Personality Traits/Sentiment/Aspectの結果＋OCEAN_hatを用い、CBT/WOOP/If–Thenから選択し自然文生成。 / RapidAPI


FR4 KPI: 実行率、連続日数、Cohen’s d（前後差）、EWMA/傾き/分散を週次集計。


FR5 オーケストレーション: n8nでWebhook→Function→HTTP Request→MySQL→通知→定期集計、一連の自動化と再試行。 / docs.n8n.io+1


受け入れ条件（例）
Baseline完了後にOCEAN/ファセット/信頼性/採点日時が永続化されること。


Symanto呼出失敗時に指数バックオフで最大N回再試行、429に適切対応。 / docs.n8n.io


OCEAN時系列は「参照のみ」で、書き込みは測定パイプラインのみ。


6. 非機能要件（NFR）
信頼性: 外部APIは指数バックオフ/タイムアウト/レート制限対応。 / docs.n8n.io


整合性: 0–1（機械）とT（人向け）を二系統保持、scale_type/norm_versionを必須メタで保存。


可観測性: 全API I/O、方策選択、LLMプロンプトを監査テーブルに保存。


性能: 同時100ユーザー想定、n8n HTTP Requestでバッチ/ループ最適化。 / docs.n8n.io


エビデンス準拠: Big Five安定性（短期は高い再検査信頼性）、JITAI、Implementation Intentionsの根拠。sciencedirect.com+2pmc.ncbi.nlm.nih.gov+2


7. データ要件（概要）
主テーブル: baseline_profiles / text_personality_estimates / ocean_timeseries（参照専用）/ behavior_kpis 等。


注意点: n8nのMySQLノードはDECIMALを文字列として返す仕様があるため型取扱いに注意。 / docs.n8n.io


8. 外部インタフェース要件
Symanto APIs（Big Five / Communication Style / Personality Traits / Sentiment / Aspect）。 / RapidAPI+2Symanto - Psychology AI+2


LLM Responses API（介入カード自然文生成）。 / platform.openai.com+1


n8n HTTP Request / MySQLノード（ワークフロー実装）。 / docs.n8n.io


9. リスク・制約
翻訳を介した推定の不確実性増大（分散へ反映）。


APIレート制限、外部依存障害、個人データの最小保持。



機能設計書（AIコーチ / v1.0）
1. 全体アーキテクチャ
クライアント（Mobile Web）— n8nワークフロー群（Onboarding/Measure/Planner）— 外部API（Symanto群・LLM Responses）— MySQL（Baseline Store / OCEAN時系列〔参照のみ〕/ KPIログ）。


2. フロー詳細設計
図1 オンボーディング
入力: IPIP-NEO-120（120項目）


処理: Webhook受信→検証/正規化→MySQL INSERT→baseline_id生成→handoff（baseline_id, user_id）。


出力: Baseline Store（OCEAN/ファセット/信頼性）。


図2 日次測定
入力: チャット発話


処理: 言語判定/翻訳→Symanto Big Five→0–1/T正規化→Prior（Baseline）と統合→確信度/分散/EWMA/直近傾向を計算→時系列保存→handoff（OCEAN_hat, confidence）。


API: Symanto Big Five（RapidAPI）RapidAPI / n8n HTTP Request。docs.n8n.io


図3 介入・エンゲージメント
入力: OCEAN_hat/信頼度 + 同一発話のCS/PT/Sentiment/Aspect
※CS = Communication Style（語り口・意図のタイプを判別するAPI）。RapidAPI+1
PT = Personality Traits（文章から意思決定様式や価値観＝特性を推定するAPI）。RapidAPI+1
※どちらも Symanto のエンドポイントとして設計に組み込まれています。



処理: Plannerで方策スコアリング→CBT/WOOP/If–Then決定→LLM Responses APIで介入カード生成→通知→KPI保存。 / platform.openai.com


3. スコア正規化とベイズ統合
正規化: IPIP採点→z→T（50±10）。Symanto出力を0–1へ、必要に応じTへ線形キャリブレーション。 / ipip.ori.org


統合（各因子ごと）:


事前平均 μ_prior、分散 σ²_prior（Baselineの信頼性に応じ設定）


観測 x（Symanto 0–1 or T）、観測分散 σ²_like（テキスト長・翻訳経路・一致度等から推定）


事後: μ_post = (σ⁻²_like·μ_prior + σ⁻²_prior·x) / (σ⁻²_like + σ⁻²_prior)
 σ²_post = 1 / (σ⁻²_like + σ⁻²_prior)


μ_postを0–1とTの二系統で保持、時系列は参照のみ。


4. データモデル（抜粋）
baseline_profiles（PK: user_id, administered_at）：OCEAN_T、OCEAN_p01、facet、信頼性、norm_version 等。


text_personality_estimates（PK: user_id, ts）：ocean_estimate、ocean_estimate_p01、lang_route、api_model。


ocean_timeseries（PK: user_id, ts）：mu_post_T、mu_post_p01、var_post、ewma_14、slope_7d。


behavior_kpis（PK: user_id, ts, technique）：executed、latency_sec、ocean_snapshot、sentiment、aspects。


5. n8n ワークフロー実装（要点）
Onboarding: Webhook→Function（採点/正規化）→MySQL（INSERT）→handoff。


Measure: HTTP Request（Symanto）→Function（正規化/統合）→MySQL（時系列UPSERT）。 / docs.n8n.io


Planner: HTTP Request（CS/PT/Sent/Aspect）→Function（方策スコアリング）→HTTP Request（/v1/responses）→MySQL（KPI）。 / platform.openai.com


運用: Cronで日次/週次集計、すべて監査ログ化。


6. 外部API仕様（例）
Symanto Big Five: POST /big-five-personality-insights（RapidAPI、キー認証）。入出力はテキスト→OCEAN推定。RapidAPI


Communication Style / Personality Traits / Sentiment / Aspect: それぞれ対応エンドポイントで同一テキストを送信。RapidAPI+1


LLM Responses API: POST /v1/responses、プロンプトは技法（CBT/WOOP/IFTHEN）、トーン、OCEAN、当日ムード/話題を入力。 / platform.openai.com+1


7. 介入プランナーのロジック（骨子）
入力: OCEAN_hat＋confidence、CS/PT、文レベル極性、話題×感情、直近KPI。


方策スコア例:
 scoreCBT = a1*NegSent + a2*Rumination + a3*HighN + a4*TopicAvoid など。


エビデンス: JITAIの原理、Implementation Intentions（If–Then）、WOOP/MCIIの効果。pmc.ncbi.nlm.nih.gov+1


8. 通知・KPI・可視化
Push通知の送出記録、実行率/継続日数、週次T推移、EWMA/傾き/分散のダッシュボード。


9. セキュリティ・運用
APIキーは安全管理、ログ監査、バックアップ/冗長化。


10. テスト計画
単体: 採点/正規化/ベイズ更新、Symantoレスポンスのスキーマ検証。


統合: n8n↔Symanto、n8n↔MySQL、Responses API。


E2E: 登録→測定→介入→KPI集計→可視化。
