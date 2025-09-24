# システムフロープレイブック（日本語版）

## 1. システム全景
- AIコーチはモバイルWebクライアント、n8nオーケストレーション、MySQLデータスタックを横断し、Symanto分析APIとOpenAI Responses APIを介入配信に活用する構成です。【F:README.md†L23-L34】【F:README.md†L36-L39】
- 内部ロジックは正規化、ベイズ結合、確信度ヒューリスティクス、ドリフト特徴量、介入計画、LLM後処理、KPI分析、データ不変条件、信頼性制御を担う9つの必須モジュール（A〜I）と、n8nフローやUI、外部サービスを束ねる補助モジュール（J〜N）から成ります。【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L1-L58】

## 2. エンドツーエンドの流れ
### 2.1 オンボーディングと基準値
1. ユーザーがクライアントでIPIP-NEO-120質問票を完了すると、モジュールAが回答を採点し、Tスコア（50±10）と0〜1スケールに変換、ノルム版をタグ付けし入力を検証します。【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L2-L4】
2. 基準値レコードはモジュールH経由で追記専用として保存され、`scale_type ∈ {T, p01}`や値域制約をMySQLの制約・トリガーで保証します。【F:docs/specification/algorism/H. データモデルと不変条件の実装†L22-L83】
3. この事前分布が後続フローにおけるベイズ更新とダッシュボードの基準となります。【F:docs/specification/algorism/B. ベイズ統合†L7-L17】

### 2.2 日次測定パイプライン
1. ユーザーチャットテキストが到着すると、モジュールAがSymanto出力を再正規化し、オンボーディングスコアと同じ0〜1/Tの二重スケールに揃えます。【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L2-L6】
2. モジュールCはトークン長、翻訳ルート、較正メトリクス、OODシグナルを基に観測品質を評価し、特性ごとの分散推定と品質フラグを計算してベイズ結合の重み付けに活用します。【F:docs/specification/algorism/C. 確信度推定と品質ルール†L3-L115】
3. モジュールBが事前分布と日次尤度を精度重み付き平均で結合し、分散をバウンド、メタデータを記録し、人間・機械両方のスケールを持つ事後分布を`ocean_timeseries`に永続化します。【F:docs/specification/algorism/B. ベイズ統合†L3-L83】
4. モジュールDはEWMA、短窓スロープ、ローリング分散、必要に応じた変化点フラグを算出し、最新のトレンド文脈をダッシュボードと介入プランナーに提供します。【F:docs/specification/algorism/D. ドリフトとトレンド検知の時系列特徴量†L1-L115】

### 2.3 介入とエンゲージメントループ
1. モジュールEが事後スナップショット、確信度フラグ、ドリフト指標、Symanto特徴量（Communication Style、Personality Traits、Sentiment、Aspect）を受け取り、JITAIの原則に沿ったCBT/WOOP/If–Then戦術をトーン・長さ制約込みで選定します。【F:docs/specification/algorism/E. 介入プランナー（JITAIの中核）†L7-L133】【F:docs/specification/symantoAPI/HowToUse†L3-L26】
2. プランナーは構造化プロンプトと根拠タグをOpenAI Responses APIへ渡し、モジュールFがスキーマ準拠JSON、モデレーション、サニタイズ、トーン・長さの正規化、多段フェイルオーバー、完全な監査証跡を担保して配信します。【F:docs/specification/algorism/F. LLM出力の後処理（Post-processing）†L1-L133】
3. 配信カード、ユーザーアクション、根拠メタデータはKPI集計（モジュールG）と再送安全性（モジュールH）のために冪等イベントテーブルへ記録されます。【F:docs/specification/algorism/G. KPI集計と評価†L3-L86】【F:docs/specification/algorism/H. データモデルと不変条件の実装†L24-L125】
4. モジュールIはSymanto、OpenAI、通知などすべての外部呼び出しを再試行予算、指数バックオフ＋ジッター、サーキットブレーカー、トークンバケット制御、冪等キーでラップし、ループ全体の堅牢性を保ちます。【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L1-L103】

## 3. モジュール早見表
| モジュール | 役割 | 主な入力 | 主な出力 | ガードレール |
| --- | --- | --- | --- | --- |
| A | IPIP & Symantoスコアの正規化、スケールメタデータ管理 | 質問票回答、Symantoスコア | 二重スケールOCEANベクトル、ノルムメタデータ | 入力検証、欠損値ハンドリング |【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L2-L6】
| B | 事前分布と日次尤度のベイズ結合 | 事前/分散、観測/分散、メタ情報 | T & 0–1の事後平均・分散、ログ | 分散キャップ、決定論的更新 |【F:docs/specification/algorism/B. ベイズ統合†L3-L108】
| C | 確信度・品質ゲーティング | 正規化済み観測、メタ情報（トークン、QE、OOD） | 特性ごとの分散、確信度、フラグ | トークン/QE閾値、較正チェック |【F:docs/specification/algorism/C. 確信度推定と品質ルール†L3-L123】
| D | ダッシュボードと計画用のドリフト特徴量 | 事後時系列、λ、窓幅 | EWMA、スロープ、ローリング分散、フラグ | SPC閾値、変化点検出（任意） |【F:docs/specification/algorism/D. ドリフトとトレンド検知の時系列特徴量†L1-L129】
| E | JITAI型介入プランナー | OCEAN推定、分散、フラグ、CS/PT、センチメント、トレンド | 技法、トーン、長さ、CTA、LLMプロンプト、根拠 | 低確信度でのセーフティクリップ、バンディット拡張計画 |【F:docs/specification/algorism/E. 介入プランナー（JITAIの中核）†L3-L147】
| F | LLM出力の後処理と安全性確保 | プランナープロンプト出力、生のLLM JSON | 検証済みカードペイロード、サニタイズ済みテキスト、監査バンドル | 構造化出力、モデレーション、DOMPurify、フェイルオーバー |【F:docs/specification/algorism/F. LLM出力の後処理（Post-processing）†L1-L134】
| G | KPI集計と実験管理 | 行動イベント、プランナーメタデータ、トレンド | 実行率、リテンション、連続達成、A/B指標 | Wilson信頼区間、CUPED、のぞき見防止 |【F:docs/specification/algorism/G. KPI集計と評価†L3-L95】
| H | データ不変条件と永続化 | モジュール出力、再試行メタデータ | 追記専用ストア、監査ログ、ロール管理 | CHECK/FK/UNIQUE、トリガー、GDPR最小化 |【F:docs/specification/algorism/H. データモデルと不変条件の実装†L1-L140】
| I | 信頼性シェル | 外部/内部APIへのHTTPリクエスト | 再試行ラップ済みレスポンス、スロットル判断 | 再試行分類、ジッター付バックオフ、サーキットブレーカー |【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L1-L103】

## 4. データライフサイクル管理
- `baseline_profiles`と`ocean_timeseries`はスケール境界、追記専用、ロール分離アクセスを徹底し、更新試行時はSQLSTATE 45000で拒否します。【F:docs/specification/algorism/H. データモデルと不変条件の実装†L24-L105】
- 行動イベントは`idempotency_key`で再試行を無害化し、モジュールIのポリシーがAPI再呼び出しの安全なリプレイを保証します。【F:docs/specification/algorism/H. データモデルと不変条件の実装†L84-L125】【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L40-L103】
- 監査ログは入力から配信カードまでの全経路を30日以上保持し、OWASP安全なログ指針とGDPR最小化方針に整合させます。【F:docs/specification/algorism/H. データモデルと不変条件の実装†L35-L140】

## 5. 分析とフィードバックループ
- 実行率、連続達成、リテンション、効果量指標を日次/週次で再計算し、Wilson区間とCUPED調整を適用、EWMAトレンドをプランナーとステークホルダーへ提示します。【F:docs/specification/algorism/G. KPI集計と評価†L27-L86】
- プランナーの高度化（LinUCB/Thompson）は、これらの報酬と記録済み根拠タグを利用し、確信度と事後分散が許す範囲で安全な探索を実施します。【F:docs/specification/algorism/E. 介入プランナー（JITAIの中核）†L67-L133】【F:docs/specification/algorism/G. KPI集計と評価†L41-L86】

## 6. 外部サービス活用戦略
- SymantoエンドポイントはBig Five指標に加え、Communication Style、Personality Traits、Sentiment、Aspectシグナルを提供し、トーン設定と戦術選定、マイクロ介入トリガーの判断に寄与します。【F:docs/specification/symantoAPI/HowToUse†L3-L26】
- OpenAI Responses APIはモジュールFのスキーマガードレール下で構造化カードを生成し、モデレーションとサニタイズでOWASP LLM02リスクを軽減します。【F:docs/specification/algorism/F. LLM出力の後処理（Post-processing）†L1-L133】

## 7. 信頼性プレイブック
- 再試行はGoogle/AWSガイダンスに従い、408/429/5xx/タイムアウトなどの一時的失敗のみ対象、`Retry-After`を尊重し、ジッター付き指数バックオフで最大3回まで試み、サーキットブレーカーとトークンバケットで輻輳を抑えます。【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L23-L103】
- n8nワークフローノードでは「Retry on Fail」と待機ステップを有効化できますが、堅牢なHTTPクライアント側でも冪等キーとバックオフロジックを維持します。【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L93-L103】

## 8. 実装ロードマップ
1. 正規化（A）、ベイズ結合（B）、確信度ヒューリスティクス（C）を同時にリリースし、相互依存する測定パイプラインを開通させます。【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L40-L45】
2. ドリフト分析（D）とKPI集計（G）を追加し、事後ストリームの可観測性とプランナーテレメトリを確保します。【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L40-L43】
3. ルールベースプランナー（E）とLLMハードニング（F）を提供し、安定後にKPIフィードバックループを使ったコンテキストバンディットへ段階的に移行します。【F:docs/specification/algorism/E. 介入プランナー（JITAIの中核）†L32-L147】【F:docs/specification/algorism/F. LLM出力の後処理（Post-processing）†L1-L133】
4. データ不変条件（H）と信頼性レイヤー（I）を固め、再試行ワークフローと分析の信頼性を本番環境で担保します。【F:docs/specification/algorism/H. データモデルと不変条件の実装†L1-L140】【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L1-L103】

## 9. 時系列サマリ
| フェーズ | トリガー | 出力 | 可観測性 |
| --- | --- | --- | --- |
| 基準確立週 | IPIP-NEO-120完了 | `baseline_profiles`、キャッシュ済み事前分布 | MySQL制約、監査ログエントリ |【F:docs/specification/algorism/1) コア：必ず社内で実装・保守するロジックとプログラム†L2-L4】【F:docs/specification/algorism/H. データモデルと不変条件の実装†L24-L83】
| 日次チェックイン | チャット投稿処理完了 | 事後分布＋ドリフト指標 | EWMA/スロープダッシュボード、品質フラグ |【F:docs/specification/algorism/C. 確信度推定と品質ルール†L3-L115】【F:docs/specification/algorism/D. ドリフトとトレンド検知の時系列特徴量†L1-L115】
| 介入配信 | プランナー決定の実行 | 構造化カード、根拠タグ | モデレーションログ、KPIイベント |【F:docs/specification/algorism/E. 介入プランナー（JITAIの中核）†L7-L125】【F:docs/specification/algorism/F. LLM出力の後処理（Post-processing）†L28-L120】【F:docs/specification/algorism/G. KPI集計と評価†L3-L86】
| 信頼性ループ | APIリクエストが制限/失敗に遭遇 | 再試行スケジュール、トークンバケット状態 | 再試行ログ、サーキットブレーカーステータス |【F:docs/specification/algorism/I. エラー制御・再試行・レート制限†L1-L103】
