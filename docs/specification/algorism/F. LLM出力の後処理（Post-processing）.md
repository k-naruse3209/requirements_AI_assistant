# F. LLM出力の後処理（Post-processing） 

F. LLM出力の後処理（Post-processing）とは？
ひとことで：LLM（Responses API）の“生の出力”を、
1. 形をそろえる（構造化・スキーマ検証）、2) 安全にする（モデレーション＆サニタイズ）、3) 読みやすくする（トーン・長さ・表記の整形）、4) 壊れないようにする（エスケープ・リンク化・フォールバック）、5) 監査可能にする（根拠タグとログ化）——までやり切る仕上げ工程です。
* 構造化は「Structured Outputs（JSON Schema）」を使って、LLMに“この形だけで出して”と縛り、機械で壊れないJSONにします（JSONモードより強制力が高いのがポイント）。Azure OpenAIの公式ガイドにも、OpenAIと同一のサブセット仕様が明記されています。Microsoft Learn+1
* 安全性はOpenAIのModeration API（omni-moderation-latest）で出力の最終チェックをかけ、危険カテゴリーを検知します（多言語・画像含むマルチモーダル判定に対応）。OpenAI+1
* セキュリティはOWASP LLM Top 10の「LLM02: Insecure Output Handling」などに沿って、HTMLサニタイズ（DOMPurify）と出力エンコードでXSS等を防ぎます。OWASP+2OWASP Cheat Sheet Series+2

どこに置かれ、何と連携する？

```text
E: 介入プランナー（technique/tone/length/CTA 決定）
  |
  |__ プロンプト（+根拠タグ） → Responses API（LLM生成）
  v
F: LLM出力の後処理（本モジュール）
  ├─ 1) 構造化・検証（Structured Outputs / JSON Schema）
  ├─ 2) 安全化（Moderation API, XSSサニタイズ）
  ├─ 3) 可読化（トーン/表記/リンク化）
  ├─ 4) フォールバック（再生成・テンプレ）
  └─ 5) 監査ログ（入出力・判定理由・スキーマ版）
        |
        ├─ クライアント配信（Mobile Web通知/カード表示）
        └─ KPIロギング（実行→継続→報酬）
```

擬似コード（フォールバック例・可読）

```js
// スキーマ検証 → 再生成 → テンプレ の段階的フォールバック例（疑似）
function finalizeCard(llmRaw, schema, moderation) {
  const validated = validateWithSchema(llmRaw, schema);
  if (validated.ok) return sanitizeAndReturn(validated.json, moderation);

  const retry = regenerateWithLowerTemp();
  const validated2 = validateWithSchema(retry, schema);
  if (validated2.ok) return sanitizeAndReturn(validated2.json, moderation);

  // 安全テンプレにフォールバック
  const safe = buildSafeTemplate();
  return sanitizeAndReturn(safe, moderation);
}
```
* 上流：Eから「選んだ介入・トーン・長さ・CTA」＋根拠タグ。
* 本モジュール：形・安全・可読性・耐故障・監査の5点チェックで仕上げる。
* 下流：配信用API（カードJSON）と監査/評価テーブルに保存。
* 横断：エラー/リトライ、レート制御、A/B振り分けはn8n側で共通実装。

どう作る？（実装ロードマップ）
1) 出力の形をそろえる：Structured Outputs（JSON Schema）
* Responses API呼び出し時に response_format: { type: "json_schema", json_schema: {..., "strict": true } } を指定。**“スキーマ通り以外は出さない”**ので、後段のパース失敗が激減します（JSONモードより堅牢）。Azure OpenAIのドキュメントに、サポートされるスキーマのサブセット（additionalProperties: false 必須、深いネスト・一部キーワード制限等）が整理されています。これを前提にスキーマを設計してください。Microsoft Learn+1
* スキーマ例（介入カード）
    * technique（enum: CBT/WOOP/IFTHEN）
    * headline（string, 1行）
    * steps（array of string, 3–5項目）
    * cta_time（string, “21:00 になったら…”）
    * explain_tags（array of string: 選定根拠）
* 実務Tip：SDKやAgentsで自動生成されるスキーマはAPI側の検証要件とズレることがあります。**APIが返す400（Invalid schema）**を拾って、ビルド時にスキーマLintを走らせると安全です。GitHub+1
2) 安全にする：モデレーション & サニタイズ
* 出力モデレーション（サーバ側）
    * LLMの出力テキストをModeration APIへ送り、unsafeならブロックまたは弱体化再生成。新しい omni-moderation-latest は多言語・画像対応で精度が向上。OpenAI+1
* XSS対策（クライアント側レンダリング直前）
    * 出力がMarkdown/HTMLを含むなら、DOMPurifyでサニタイズし、OWASPのXSS防止チートシートに沿ってコンテキスト別エンコードを適用（属性値/URL/HTML本文など）。GitHub+1
    * 「出力の取り扱いを信頼せず必ず検証する」は**OWASP LLM Top 10（LLM02）**の基本原則です。OWASP
3) 読みやすくする：表記・トーン・リンク化
* 表記ゆれ（箇条書きの記号、全角/半角、敬体/常体）を正規化フィルタで整える。
* 長さの統制（短/中/長）はルールで切る：文字数・ステップ数の上限下限を後処理で厳守。
* CTAのリンク化/日付解決：21:00 などを**ユーザーのTZ（Asia/Tokyo）**で日時に変換し、通知深リンクに加工。
    * ※「UIでHTMLを生成する部分」は常にサニタイズ後に挿入（再掲）。OWASP Cheat Sheet Series
4) 壊れないようにする：フォールバックと再生成
* 段階的フォールバック
    1. スキーマ違反 → 同一プロンプトで1回だけ再生成（温度低め）
    2. モデレーションNG → 安全テンプレ（短い励まし＋リマインド）
    3. サニタイズで空 → テキストのみテンプレ
* ログにどの段で止まったか（schema_fail/moderation_fail/sanitize_empty）を残し、改善に回す。
5) 監査可能にする：根拠タグ & 完全ログ
* LLMへ渡した入力要約（OCEAN_hat/Sentiment/Aspect/時系列特徴のサマリ）と、プランナーの選定根拠タグを出力にも転載（ユーザー表示は省略可）。
* 保存：inputs → llm_raw → schema_validated → moderation → sanitized → delivered の各スナップショットと判定結果を非改ざんストアに保存（最低30日）。

n8nでの処理ブロック設計（擬似コード）

// 0) LLM呼び出し（Responses API）…Eモジュールからのプロンプト
// response_format: json_schema (strict: true) を設定済み

// 1) スキーマ検証（SDKが返すparsed or 400）
if (!parsed) retry_once_or_fallback();

// 2) モデレーション
const mod = moderate(parsed.headline + "\n" + parsed.steps.join("\n"));
if (mod.flagged) return fallback_safe_template(mod.categories);  // 安全テンプレ

// 3) サニタイズ（クライアントで再実施）
const safeHeadline = sanitize(parsed.headline);
const safeSteps = parsed.steps.map(sanitize);

// 4) 可読化ルール
const trimmed = enforceLength({ headline: safeHeadline, steps: safeSteps }, {maxSteps:5, maxChars:280});

// 5) 出力
return {
  card: {...trimmed, technique: parsed.technique, cta_time: parsed.cta_time},
  rationale: parsed.explain_tags,
  audit: { moderation: mod }
};

スキーマ例（抜粋）

{
  "name": "intervention_card",
  "strict": true,
  "schema": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
      "technique": { "type": "string", "enum": ["CBT","WOOP","IFTHEN"] },
      "headline": { "type": "string" },
      "steps": {
        "type": "array",
        "items": { "type": "string" },
        "minItems": 3, "maxItems": 5
      },
      "cta_time": { "type": "string" },
      "explain_tags": { "type": "array", "items": { "type": "string" } }
    },
    "required": ["technique","headline","steps","cta_time","explain_tags"]
  }
}
注意：Structured Outputsでは**additionalProperties:falseが必須**、深いネストや一部キーワードが制限されます。OpenAI/ Azure OpenAIの“構造化出力”仕様のサブセットに合わせて設計してください。Microsoft Learn

品質・セキュリティの要点（根拠つき）
* “LLM出力をそのまま信じない”：OWASP LLM Top 10は出力の不適切処理（Insecure Output Handling）とプロンプトインジェクションを主要リスクに掲げています。必ず検証→サニタイズを通してください。OWASP+1
* モデレーションの二重化：入力（ユーザー投稿）だけでなく出力にもModerationをかけるのがOpenAIの推奨パターンの一つです。新しいomni-moderation-latestは多言語・画像の安全判定が強化されています。OpenAI Cookbook+1
* XSS防御の基本：サニタイズ（DOMPurify）＋文脈別エンコードがOWASP推奨の王道です。フロントのレンダリング直前にも適用しましょう。GitHub+1
* 構造化の推奨：**Structured Outputsは“JSONモードの進化系”**で、スキーマ順序どおりに出力され、厳格な整合性を担保できます（モードの違いに注意）。Stack Overflow

受け入れ基準（例）
1. スキーマ完全一致率：Responses API→100%スキーマ適合（再生成1回までは許容）。違反時はフォールバックが発火する。Microsoft Learn
2. 安全基準：Moderationが全配信出力に適用され、NG時は安全テンプレで配信される。omni-moderation-latestを使用。OpenAI
3. XSS耐性：クライアント側でDOMPurifyサニタイズ＋OWASPの出力エンコードを適用。社内ペネトレで一般的ペイロードを無害化。GitHub+1
4. 可読性：Eが指定した長さ・トーン・構成を後処理で保証（ステップ数・記号・敬体）。
5. 監査性：inputs → llm_raw → schema_validated → moderated → sanitized → delivered の各段階のスナップショットと判定ログが残る。

よくある落とし穴と対処
* 「JSONモード」と「Structured Outputs」の混同 → 後者を推奨。必ずスキーマをAPIに渡す。エラーは400で返るのでCIで検証。Stack Overflow+1
* 自動生成スキーマの不整合（Agents/SDK） → 生成物をLintし、additionalProperties:falseや必須列挙を満たすよう修正。GitHub
* サニタイズ抜け（サーバでOKでも、フロントで危険） → レンダリング直前にもDOMPurifyを適用。GitHub

整合性チェック（5回）
1. アーキ整合：E→（LLM生成）→F→配信の直列配置。Fは**LLM出力の“形・安全・可読・耐故障・監査”**の5役を担う。OK。
2. 外部仕様：Structured Outputs（JSON Schemaのサブセット要件）とModeration API（omni-moderation-latest）の一次資料に合致。OK。Microsoft Learn+1
3. セキュリティ原則：OWASP LLM Top 10（LLM02/LLM01）とOWASP XSS対策に基づく出力検証＋サニタイズを実装。OK。OWASP+1
4. 運用性：スキーマ→再生成→安全テンプレの多段フォールバックと完全監査ログを明記。OK。
5. ユーザー体験：トーン/長さ/CTAを後処理で確実化し、TZ（Asia/Tokyo）に合わせる実務要件を記載。OK。

必要なら、このFモジュールをn8n Functionノード用コード＋JSON Schema一式＋**モデレーション/サニタイズの実装例（サーバ&フロント）**に落としてお渡しできます。
