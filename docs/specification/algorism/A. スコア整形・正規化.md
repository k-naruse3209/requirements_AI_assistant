# A. スコア整形・正規化 

A. スコア整形・正規化

役割 ユーザーの回答やテキスト解析の**“生データ”を、人にも機械にも一貫して使えるスコアに整える共通基盤**です。
* 人向け表示：Tスコア（平均50・標準偏差10の0–100表示）に変換してグラフや説明に使う。ipip.ori.org
* 機械向け学習：0–1の正規化スコア（p01）を作り、後段の推定・判定に使う。
* メタ情報：norm_version（規準データの版）を付け、解釈ミスや二重正規化を防ぐ（T/p01は常に列として両方保存）。
どこに置かれている？ 全体アーキテクチャの中央（n8nワークフローのFunction/HTTPノード近辺）で、**図1（初回のIPIP採点）と図2（Symantoのテキスト推定）**の両方で動きます。

どう他システムと連携している？（データの流れ）
1. オンボーディング（図1）
* Mobile WebのIPIP-NEO-120回答がn8n Webhookに届く → スコア整形・正規化で採点・T化・0–1化 → baseline_profilesに保存 → baseline_id, user_idを図2へハンドオフ。
1. 日次測定（図2）
* 日々の発話をSymanto Big Five APIに送る → OCEANの推定が返る → スコア整形・正規化で0–1/Tに統一 → Baseline（Prior）と合わせる統合へ渡す（※統合そのものは項目B）。結果はocean_timeseriesに保存し、図3へOCEAN_hatをハンドオフ。
    * Symanto Big Fiveの外形仕様：テキストからOCEANを推定するAPI。RapidAPIにも掲載。Symanto - Psychology AI+3rapidapi.com+3rapidapi.com+3
1. 介入（図3）
* プランナーはocean_timeseriesのT表示や0–1を参照して、CBT/WOOP/If–Thenの介入を選択し、LLMで自然文に整える。整形・正規化は参照される立場。
n8nのHTTP Request/MySQLノードでAPI連携・DB保存を実装（429・タイムアウト等はリトライ）。n8n Docs+1 MySQLノードはDECIMALを文字列で返す仕様（精度保護のため）なので、数値変換の扱いを「整形」で吸収します。n8n Docs+2GitHub+2

どう構築する？（実装ガイド：I/O設計 → 手順 → 擬似コード）
1) I/O（インターフェース）設計
① Onboarding入力 → Baseline出力
* 入力（例）: ipip_answers（120項目の {item_id, value}、Likert 1–5）
* 出力（例）:

{
  "user_id": 123,
  "instrument": "IPIP-NEO-120",
  "administered_at": "2025-09-16T09:00:00Z",
  "ocean_T": {"O":63,"C":44,"E":52,"A":58,"N":41},
  "ocean_p01": {"O":0.63,"C":0.44,"E":0.52,"A":0.58,"N":0.41},
  "facet_scores": { "O1": 56, "...": 47 },
  "norm_version": "Johnson2014"
}
* 根拠：IPIPスコアキー/規準（Johnson 2014）に従い、z→T=50+10zに変換。ipip.ori.org+2ipip.ori.org+2
* 保存先：baseline_profiles（仕様書・DDLに準拠）。
② Measure入力（Symanto） → 正規化出力
* 入力（例）：symanto_raw = {"O": 0.71, "C":0.33, "E":0.49, "A":0.62, "N":0.28}
* 出力（例）：
    * ocean_estimate_p01（0–1維持）、必要に応じてTへ線形キャリブレーションしたocean_Tを併記。
* 根拠：Symanto Big FiveのAPI仕様（OCEAN推定を返す）。rapidapi.com+1
* 保存先：text_personality_estimates → 統合（B）にハンドオフ。
2) 実装手順（n8n + JS Function前提）
Step A-1｜入力検証
* 必須項目数（120/120）、値域（1–5）、逆転項目の存在チェック、欠損処理（中央値補完は避け、未回答は採点除外）。
Step A-2｜採点（IPIP）
1. 逆転処理：score = 6 - value（逆転項目のみ）。
2. ファセット集計：4項目×30ファセットの合計/平均。
3. z→T変換：z = (raw - μ_norm)/σ_norm、T = 50 + 10*z。規準はJohnson系の公開データに準拠。ipip.ori.org+1
4. 0–1化：p01 = (T / 100)（単純スケーリング。後段の回帰/融合で扱いやすい）。
5. メタ付与：norm_version="Johnson2014"。
Step A-3｜正規化（Symanto）
* 0–1の受領値をそのままp01として採用。T化が必要なら線形キャリブレーション（例：T ≈ 100*p01を初期近似にし、パイロットで回帰補正）。API外形はRapidAPI/Symanto公開情報に一致。rapidapi.com+2rapidapi.com+2
Step A-4｜DB保存
* n8nのMySQLノードでINSERT/UPSERT。DECIMALは文字列で返る仕様を把握し、後続でNumber()に統一変換。n8n Docs
* 保存テーブルは仕様書どおり：baseline_profiles / text_personality_estimates。
Step A-5｜エラー・再試行
* HTTP 429/5xxは指数バックオフ（n8n HTTP Request推奨設定）。n8n Docs+1
3) 擬似コード（要点のみ）

// Onboarding: IPIP -> T & p01
function normalizeIpip(answers, norms){ // norms: {mu, sigma} per facet/domain
  const scored = scoreIpip(answers);       // reverse-key & sum/avg per facet
  const oceanRaw = rollupToDomains(scored); // O,C,E,A,N raw
  const oceanT   = mapValues(oceanRaw, (x,k)=> 50 + 10*((x - norms[k].mu)/norms[k].sigma)); // T
  const oceanP01 = mapValues(oceanT, t => Math.min(1, Math.max(0, t/100)));
  return { oceanT, oceanP01, norm_version: "Johnson2014" };
}

// Measure: Symanto -> p01 (& optional T)
function normalizeSymanto(ocean){ // ocean in 0..1
  const oceanP01 = clamp01(ocean);
  const oceanT   = mapValues(oceanP01, p => p * 100); // start with linear T
  return { oceanT, oceanP01 };
}
IPIP採点と規準（μ, σ）はIPIP公式リソースを参照。ipip.ori.org+1

品質保証（ミニ受け入れテスト）
* Tの平均が規準母集団で約50、SDが約10になること（テスト用ダミー分布で検証）。ipip.ori.org
* **p01 ∈ [0,1]**の境界保証（丸め誤差±1e−6まで）。
* DECIMAL→文字列の扱いを統一（保存前後で型チェック）。n8n Docs
* 再現性：同一入力→同一出力（小数点以下の許容誤差内）。
* メタ：norm_versionが常に埋まる。

参照と裏付け
* アーキテクチャ＆フロー（社内資料）：全体図・図1・図2・図3・仕様書2.0/2.1。 
* IPIPの使い方・採点・規準：IPIP公式（How to score / Johnson 2014 / Norms）。ipip.ori.org+2ipip.ori.org+2
* Symanto Big Five API（機能概要・Playground・公式サイト）。Symanto - Psychology AI+3rapidapi.com+3rapidapi.com+3
* n8n（HTTP Request/実装例、MySQLのDECIMAL文字列仕様）。n8n Docs+2n8n Docs+2

整合性チェック（5回の観点）
1. 単位の一貫性：IPIP→T/p01、Symanto→p01/T（線形初期化）。両方を列で保持し、norm_versionメタで整合。二重正規化や誤解釈を防止。OK。
2. フロー整合：図1（Baseline）→図2（Measure）→図3（Plan）で、Aは図1・図2の共通部品として働く。OK。
3. 保存戦略：baseline_profiles/text_personality_estimatesに入力ログ＋正規化値、ocean_timeseriesは“参照のみ”。OK。
4. 外部仕様整合：IPIP採点手順、Symanto APIの外形、n8nノードの挙動（HTTP/DECIMAL）。OK。n8n Docs+3ipip.ori.org+3rapidapi.com+3
5. 初心者向け説明性：目的→連携→構築の順で具体例・JSON・擬似コードを提示。用語は本文内で都度平易化。OK。

必要なら、この「A. スコア整形・正規化」をn8n Functionノードの実コード（JS）とMySQLテーブルDDLに落としてお渡しできます。
