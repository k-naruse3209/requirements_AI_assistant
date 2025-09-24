# システムフロープレイブック（日本語版）

## 1. システム全景
- 構成: Mobile Webクライアント、n8nオーケストレーション、MySQLデータ基盤。外部はSymanto分析API群とOpenAI Responses APIを利用。
- コア: 9つのモジュール（A〜I）で、正規化(A)、ベイズ統合(B)、確信度/品質(C)、時系列特徴(D)、介入プランナー(E)、LLM後処理(F)、KPI(G)、不変条件(H)、信頼性制御(I)を担当。n8nとUIが周辺を接続。

## 2. エンドツーエンドの流れ
### 2.1 オンボーディングと基準値
1. IPIP-NEO-120の採点・正規化（A）: 回答をTスコア（50±10）と0–1へ変換し、`norm_version`と`scale_type`を付与。入力検証・欠損処理を含む。
2. 保存（H）: `baseline_profiles`へ追記専用で保存。`scale_type ∈ {T,p01}`、T∈[0,100], p01∈[0,1]などをCHECK/権限/トリガで強制。
3. Prior確立（B）: 基準値はベイズ更新のPriorとして以後の測定・介入で参照。

### 2.2 日次測定パイプライン
1. チャット→分析: 言語判定/翻訳後、SymantoのBig5/CS/PT/Sentiment/Aspectを取得。Aで0–1/Tへ再正規化。
2. 品質推定（C）: トークン長、翻訳QE、OOD、言語ミスマッチ等から観測分散σx²（因子別）と品質フラグを算出。過小分散ガード（下限）と平滑化を適用。
3. ベイズ統合（B）: PriorとLikelihoodを精度重み（=1/分散）で統合し、Posterior（T/0–1両系）と分散を`ocean_timeseries`へ追記。
4. 特徴抽出（D）: EWMA、直近傾き、ローリング分散、必要に応じて変化点（CUSUM/PH/BOCPD等）を算出し、ダッシュボードとEへ渡す。

### 2.3 介入とエンゲージメント
1. プランニング（E）: Posterior・分散、確信度/品質、EWMA/傾き/分散、CS/PT、Sentiment/Aspectを入力に、JITAI原則でCBT/WOOP/If–Thenとトーン/長さ/CTAを決定。低確信度や高分散時は強度をクリップ。
2. 生成と安全化（F）: OpenAI Responsesで生成→Structured Outputs（JSON Schema）で形を強制、Moderation/XSSサニタイズ、長さ/表記の整形、段階フォールバック、監査ログ保存。
3. 記録と評価（G/H）: 配信カードとユーザー行動を冪等イベント（`behavior_events`）に記録。KPI集計（実行率/継続/Retention、A/B＋CUPED、EWMAトレンド）を行う。不変条件(H)が一意性・権限・追記専用を保証。
4. 信頼性制御（I）: Symanto/OpenAI/通知など外部呼び出しを、Retry-After尊重の指数バックオフ＋ジッター、サーキットブレーカ、Token Bucket、Idempotency-Keyでラップ。

## 3. モジュール早見表（要約）
- A: IPIP/Symantoの正規化・スケール管理（T/p01の二系統保持、検証・欠損処理）
- B: Prior×Likelihoodの精度重み統合（Posterior μ/σ²をT/0–1で保存、分散に上下限）
- C: 観測分散σx²推定と品質ゲート（トークン数/QE/OOD/言語、温度スケーリング等で校正）
- D: EWMA/傾き/分散＋（任意）変化点。ダッシュ・Eの強度調整に使用
- E: JITAIプランナー（ルール→バンディット）。トーン/長さ/CTAを制御し根拠をログ
- F: LLM後処理（Structured Outputs/Moderation/XSS/フォールバック/監査）
- G: KPI（実行率CI、Streak、Retention、効果量、CUPED、EWMA）
- H: 不変条件（値域CHECK、追記専用、UNIQUE、権限/ビュー/トリガ、監査）
- I: 再試行/レート制限/サーキット/Idempotency（429/5xx/timeout対象、Retry-After尊重）

## 4. 参照
- 仕様詳細: `docs/specification/algorism/*`（A〜I 各モジュール）
- 図面（Mermaid）: `docs/diagrams/`（分割図）

