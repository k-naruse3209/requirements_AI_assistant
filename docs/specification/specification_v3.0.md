# プロトタイプ仕様書（AIコーチ v0.3）

## 1. ドキュメント目的と整合性前提
- 中心仮説は「ユーザー回答→処理→AI応答が変化する」ことの再現であり、本ドキュメントはそのプロトタイプ構成を一貫して記述する。  
- 他ドキュメント（README、プレイブック、モジュール仕様 A〜I）と整合するよう、データフローと責務をすべて対応付けた。  
- プロトタイプ段階につき、検証仮説・成功指標は策定しない。挙動確認とフィードバック収集のみを目的とする。  
- 介入文面で使用する LLM API はエンジニア裁量で選択し、Structured Output・Moderation・監査ログ取得・フォールバックが実装できるものを前提とする。

## 2. 全体アーキテクチャ（整合確認済）
| 層 | コンポーネント | 整合ポイント |
| --- | --- | --- |
| クライアント | Mobile Web（フォーム + チャット UI） | README / プレイブック 1章 |
| オーケストレーション | n8n（Webhook, Function, HTTP Request, MySQL, Scheduler） | docs/system_flow_playbook*.md |
| コアモジュール | A〜I（正規化/ベイズ/品質/特徴/プランナー/後処理/KPI/不変条件/信頼性） | `docs/specification/algorism` |
| データ層 | MySQL（追記専用テーブル、ビュー、監査ログ） | README・仕様書 |
| 外部 API | Symanto Big Five / CS / PT / Sentiment / Aspect、LLM API（選定）、通知チャネル | README「外部サービス」 |

## 3. スコープ
### 3.1 In Scope
- Onboarding: IPIP-NEO-120 採点、正規化（A）、ベースライン保存（H）。  
- 日次測定: チャット受付、Symanto 呼び出し、正規化（A）、確信度推定（C）、ベイズ更新（B）、特徴抽出（D）。  
- 介入: プランナー（E）、LLM 呼び出し（エンジニア選定 API）、後処理（F）、信頼性制御（I）、配信ログ（G/H）。  
- 監査・オペレーター UI: すべての API I/O・プロンプト・意思決定を `audit_log` に記録し、手動レビューを担保。  
- ログリプレイ: 追記データからの再生と整合性チェック。

### 3.2 Out of Scope
- KPI・成功指標の定量追跡。  
- 自動配信（オペレーター承認なし）の本番運用。  
- 医療/PHI の厳格要件、課金/ID プロバイダ統合、プロダクション監視スタック。

## 4. 主要ステークホルダー
- エンドユーザー: 回答・日次チャットを送信。  
- オペレーター/コーチ: 介入カードのレビューと配信判断。  
- 開発/ML エンジニア: n8n フロー、Symanto 連携、LLM API 選定・実装、データ整備。  
- セキュリティ/インフラ: API キー管理、信頼性制御、監査ログ基盤。

## 5. コアフロー（A〜Iとの対応）
### 5.1 オンボーディング（図01, モジュール A/H/B）
1. Mobile Web で IPIP-NEO-120 を完了。  
2. n8n Webhook → Function で採点し、T/0–1 の二系統と `norm_version` を付与（A）。  
3. H が値域チェック + 追記 INSERT を実施し、`baseline_profiles` に保存。  
4. B が Prior として `baseline_id` を後続フローへハンドオフ。

### 5.2 日次測定（図02, モジュール A/B/C/D/I）
1. チャット入力を受信し、言語判定・翻訳。  
2. Symanto Big Five を呼び出し（I がリトライ/サーキット/レート制御）。  
3. A が 0–1/T に整形し、C が σx²・品質フラグを算出。  
4. B が Prior（Baseline or 直近 Posterior）と Likelihood を統合し `ocean_timeseries` へ追記。  
5. D が EWMA/傾き/分散/任意変化点を更新し、`ocean_features`（任意）へ保存。  
6. すべての API/計算ログを `audit_log` に記録。

### 5.3 介入生成（図03, モジュール D/E/F/I/G/H）
1. 入力: Posterior, 確信度, Symanto CS/PT/Sentiment/Aspect, 行動ログ。  
2. E が JITAI ルールで技法（CBT/WOOP/If–Then）、トーン、CTA、送信タイミングを選択し根拠タグを付与。  
3. LLM 呼び出し: エンジニア選定 API（Responses 互換）へ Structured Output で依頼。I が再試行/サーキットを担当。  
4. F が JSON Schema 検証、Moderation、XSS/リンクサニタイズ、長さ制御、フォールバック。  
5. オペレーター審査: 生成カードが `intervention_plans` のキューに入り、手動承認後に通知チャネルへ送出。  
6. G/H が `behavior_events` と `audit_log` に配信・閲覧・実行・オペレーター操作を追記。

### 5.4 データレビュー＆リプレイ
- BI/Notebook で追記テーブルを参照し、挙動を手動確認。  
- ログリプレイで再処理し、Posterior や介入内容が一致するかを整合チェックとする。  
- KPI は記録しないが、イベントログから任意に分析できる設計。

## 6. 機能要件（FR）
1. **FR1 正規化**: IPIP/Symanto 入力を T/0–1 二系統で保存し `norm_version` を付与（A）。  
2. **FR2 Prior/Pposterior 更新**: ベイズ統合で μ/σ² を `ocean_timeseries` に追記（B）。  
3. **FR3 品質推定**: σx² と品質フラグを算出してベイズ統合の重みに反映（C）。  
4. **FR4 特徴計算**: EWMA、傾き、ローリング分散、任意変化点を算出（D）。  
5. **FR5 介入プランニング**: Posterior とテキスト特徴を根拠に技法/トーン/CTA を決め、根拠タグを残す（E）。  
6. **FR6 LLM 生成+後処理**: 生成 API に Structured Output でリクエストし、Moderation/XSS/スタイル整形/フォールバック/監査を行う（F/I）。  
7. **FR7 手動承認**: すべてのカードはオペレーター承認画面を必須とし、配信結果を `behavior_events` へ記録（G/H）。  
8. **FR8 監査**: Symanto/LLM/通知の I/O、プランナー判断、ベイズ計算ログを `audit_log` に残し、リプレイできる状態にする。  
9. **FR9 Idempotency**: `idempotency_key` を各ワークフローで受け渡し、n8n の再実行でも重複挿入しない。

## 7. データモデル（抜粋）
- `users`：基本属性、同意状態。  
- `baseline_profiles`：OCEAN_T, OCEAN_p01, 30 ファセット, 信頼性, `norm_version`, `administered_at`。  
- `text_personality_estimates`：Symanto 生データ、正規化値、σx²、品質フラグ、lang_route。  
- `ocean_timeseries`：Posterior μ/σ²、EWMA、傾き、`idempotency_key`、`source_event_id`。  
- `ocean_features`（任意）: 追加特徴やデバッグ指標。  
- `intervention_plans`：プランナー出力、LLM 入力/出力、後処理ステータス、根拠タグ。  
- `behavior_events`：配信/閲覧/実行/完了、オペレーター操作、冪等キー。  
- `audit_log`：API I/O、プロンプト、再試行履歴、エラーコード。

## 8. 外部インタフェース
- **Symanto APIs**: Big Five, Communication Style, Personality Traits, Sentiment, Aspect。I が Timeout/429/5xx を監視し再試行。  
- **LLM API**: エンジニア選定（例: OpenAI Responses 互換、Anthropic、Azure 等）。条件: Structured Output, Moderation API または同等機能, フォールバック/監査ログ取得が可能。  
- **通知チャネル**: Push / Email / Webhook 等。プロトタイプでは任意だが配信ログは必須。  
- **翻訳/言語判定**（必要に応じて）: 既存スタックに合わせて自由選択。

## 9. 非機能要件
- **信頼性**: Symanto/LLM/通知呼び出しは 408/429/5xx/timeout を対象に指数バックオフ + ジッター、Retry-After 尊重、サーキットブレーカ、Token Bucket。  
- **整合性**: T と 0–1 を常に列で保持し、`norm_version` を必須。書き込みは n8n 専用フローのみ。  
- **セキュリティ/PII**: API キー秘匿、最小データ保持、Role-Based Access。  
- **可観測性**: 各ワークフローの入力/出力/実行時間/エラーを `audit_log` と n8n ログで追跡。  
- **プロトタイプ指針**: KPI は計測しない。挙動ログとオペレーター観察を優先し、改善サイクルの材料とする。

## 10. テスト・整合性検証
- **単体**: IPIP 採点、正規化、σx² 推定、ベイズ更新、プランナー意思決定、LLM 後処理。  
- **統合**: n8n ↔ Symanto、n8n ↔ LLM API、n8n ↔ MySQL。  
- **E2E 手動**: オンボーディング → 日次測定 → 介入生成 → オペレーター承認 → 配信ログ。  
- **リプレイ**: `audit_log` から入力を再投入し、Posterior/介入結果が再現されるか確認。  
- **整合チェック項目**:  
  - A〜I の責務が各フローで一意にマッピングされている。  
  - T/0–1 二系統、`norm_version`、`idempotency_key` がすべてのレコードに存在。  
  - 外部 API 呼び出しは I モジュールを必ず経由。  
  - オペレーター承認を経ずに配信される経路がない。

## 11. プロダクション対応への拡張指針
- **データ保持・分析**: 既存テーブルはそのまま本番 DB に昇格できる設計としており、ユーザー回答/チャットログ/介入ログは追記専用で保存・再分析できる。BI やモニタリング基盤にレプリカを接続するだけで、実データを用いた分析を継続できる。  
- **AI フィードバック生成**: プロトタイプで確立した A〜I モジュール分離と Structured Output/Moderation/監査要件を維持したまま、選定した LLM API を本番用クレデンシャルやスロットリング設定に切り替えることで、実利用ユーザーへのフィードバック生成が可能。  
- **運用強化ポイント**: 認証/課金、PII ガバナンス、監視・アラート、冗長化、KPI 設計を追加で実装すれば、「実際にユーザーの回答を保存・分析しながら AI からのフィードバックを生成できる」プロダクション対応構成へ段階的に拡張できる。  
- **移行手順サマリ**: (1) n8n ワークフローを本番環境にデプロイ、(2) MySQL を高可用構成に切り替え、(3) LLM/Symanto の本番キーを適用、(4) オペレーター承認フローを運用プロセスに組み込む、(5) KPI/監視を追加。この順で拡張してもプロトタイプ仕様との整合が保たれる。

---
本仕様はプロトタイプ構成の整合性を担保した設計指針であり、KPI や成功指標は必要になった段階で別途策定する。
