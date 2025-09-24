# I. エラー制御・再試行・レート制限 
これは何をするシステム？
要点：API呼び出しや外部サービス連携で起きる一時的な失敗（タイムアウト・429・5xxなど）を安全に再試行し、過負荷や“再試行嵐”を防ぎつつ成功率を上げる“交通整理”レイヤです。基礎は
* エラーカテゴリ判定（どれを再試行するか）Google Cloud
* 指数バックオフ＋ジッター（待機時間を指数的に伸ばし乱数で同時再突入を回避）Amazon Web Services, Inc.+1
* サーバの指示（Retry-After ヘッダ）尊重MDN Web Docs+1
* サーキットブレーカ（失敗が続く系への呼び出しを一時遮断）Microsoft Learn
* レート制限（Token/Leaky Bucket）で呼び出し速度を平滑にする、の5点です。Cloudflare Docs+1
429は「短時間に投げ過ぎ」の標準ステータスで、Retry-Afterに従って待つのが正道です。MDN Web Docs

他システムとの連携（どこに挟まる？）

A～H（各モジュール） →［I. エラー制御・再試行・レート制限］→ 外部API（OpenAI等）/ 内部API
                                     │
                                     ├ 失敗の分類（再試行 / 即時失敗）
                                     ├ 再試行ポリシー（指数バックオフ＋ジッター、上限回数）
                                     ├ サーキットブレーカ（Open/Close/Half-Open）
                                     └ クライアント側レート制限（Token Bucket 等）
* 上流：E（介入プランナー）、F（LLM後処理）などAPIを叩く側は全てIを経由。
* 下流：外部API（OpenAI/翻訳等）。429・5xx・タイムアウト等をIが吸収→制御します（OpenAIのレート制限対処はランダム指数バックオフが推奨）。OpenAI Cookbook
* オーケストレーション（n8n）：HTTP RequestノードのRetry on Fail/Waitで簡易レート制限も可能。公式手順あり。n8n Docs+1

どう作る？（実装ガイド）
1) まず「何を再試行するか」を決める（分類）
* 再試行すべき：408/429/5xx、タイムアウト、TCP切断＝一時的な障害。Google Cloud
* 再試行しても無駄：400/401/403/404/422など恒久的な失敗（認証・入力エラー）。—即時失敗にして原因をログへ。
* 429：Retry-Afterがあれば必ず従う（秒または日時）。なければ指数バックオフ＋ジッターで。MDN Web Docs+1
2) 再試行ポリシー（指数バックオフ＋ジッター）
* 基本形：sleep = min(cap, base * 2^attempt) + rand(0, jitter)（=上限付き指数＋ジッター）Lumigo+1
* なぜジッター？ 同時に失敗した多数クライアントが同時に再突入する“再試行嵐”を避けるため。AWS/Googleもジッター必須と明記。Amazon Web Services, Inc.+1
* 上限回数：Google SRE系の目安は1リクエストにつき最大3回、全体でも総トラフィックの10%を超える再試行は抑制。lylefranklin.com
3) サーキットブレーカ（失敗の連鎖を止める）
* Open状態では即時失敗（フォールバック文面など）→Half-Openでプローブ→Closeで復帰。Azureの設計指針が詳しい。Microsoft Learn+1
* リトライと組み合わせ：短期の再試行 → 連続失敗でブレーカOpenの順。Microsoft Learn
4) レート制限（クライアント側の“速度制御”）
* Token Bucket（バースト許容/平常は一定速度）を推奨。Cloudflareの実装例が分かりやすい。Cloudflare Docs
* Leaky Bucket（常に一定吐き出し）も選択肢。The Cloudflare Blog
* 実装要点：容量（burst）・補充レート（rps）・共有/ユーザー別のバケツをRedis等で持つ。
    * 参考理解：MDNの429の解説、Token/Leakyの違い。MDN Web Docs+1
5) Idempotency（再試行で二重処理しない仕組み）
* 同じ操作は同じ結果に：Idempotency-Key（クライアント生成の一意キー）で重複実行を防ぐのが定石（Stripe実装が代表）。Stripe Docs+1
* サーバ側はキー→結果のキャッシュを一定時間保持して再送には同じ応答を返す。Stripe
6) n8n での実装（現場向け）
* Retry on FailをON、429/5xx/タイムアウト時にWaitノードで待機→再試行。公式ガイド有り。n8n Docs+1
* ワークフローテンプレ：Google API向け指数バックオフテンプレが公開。429対策の例として使えます。n8n

具体レシピ（擬似コード・JavaScript風）
再試行（Retry-After尊重＋上限付き指数バックオフ＋ジッター）

```js
async function callWithRetry(fetcher, {base=0.5, cap=20, max=3, jitter=0.5}) {
  for (let a=0; ; a++) {
    try { return await fetcher(); }
    catch (e) {
      const code = e.status || 0;
      const ra = e.headers?.["retry-after"];              // 秒 or HTTP日時
      const retryable = [408,429,500,502,503,504].includes(code) || e.isTimeout;
      if (!retryable || a >= max) throw e;

      let delay;
      if (ra) { delay = parseRetryAfter(ra); }            // 429はまずサーバ指示に従う
      else     { delay = Math.min(cap, base * 2**a) + Math.random()*jitter; }
      await sleep(delay * 1000);
    }
  }
}
```
根拠：429/5xx/408/タイムアウトは再試行候補、指数バックオフ＋ジッター、Retry-After尊重は各公式に明記。Google Cloud+2Amazon Web Services, Inc.+2
Token Bucket（Redis想定の概念）

```text
refill tokens at rate r (per second), up to capacity B
on request:
  now = time()
  bucket.tokens = min(B, bucket.tokens + r*(now - bucket.last))
  if bucket.tokens >= 1: bucket.tokens -= 1; allow
  else: reject or delay
```
根拠：Cloudflareの実装解説（Durable Objects）やネットワーク理論で一般化。Cloudflare Docs+1

OpenAI / Azure OpenAI 連携の注意
* 429は通常のレート制限→ランダム指数バックオフで再試行。Cookbookで明示。OpenAI Cookbook
* Azure OpenAIではSKU/ティア上限に達すると具体的なRetry-After秒が返ることがある。メッセージに従う。Microsoft Learn

運用の落とし穴 → こう避ける
* 再試行嵐（Retry Storm）：ジッターを必ず入れる／上限回数を設ける。SRE本でも過剰な再試行が障害を悪化と解説。sre.google
* 全部にリトライ：恒久エラーは即時失敗。再試行予算（Budget）やサーキットブレーカで守る。lylefranklin.com+1
* レート制限を“後付け”：クライアント側レート制限（Token/Leaky）を共通ライブラリ化して横断適用。Cloudflare Docs

受け入れ基準（例）
1. 408/429/5xx/timeoutのみ再試行、400/401/403/404/422は即時失敗（ユニットテスト）。Google Cloud
2. Retry-Afterがある429は指示秒数±5%以内で待機する（結合テスト）。MDN Web Docs
3. 指数バックオフ＋ジッターで同時再突入率が無粒化（負荷試験でピーク低減を確認）。Amazon Web Services, Inc.
4. サーキットブレーカが連続失敗でOpen→Half-Open→Closeの遷移を正しく行う（フェイルオーバーテスト）。Microsoft Learn
5. Idempotency-Keyにより二重作成が0件（重送テスト）。Stripe Docs

最小構成まとめ（n8n中心のMVP）
* HTTP Requestノード：Retry on Fail有効化、429/5xxでWait→再試行（パラメタは上限回数・最大待機を設定）。n8n Docs
* グローバルWait：Loop Over Items + Waitでスループットを時間分散（事例ガイドあり）。n8n Docs
* アプリ側：共通HTTPクライアントに指数バックオフ＋ジッター・Retry-After尊重・サーキットブレーカ・Token Bucket・Idempotency-Key対応を実装。Stripe Docs+3Amazon Web Services, Inc.+3Microsoft Learn+3

整合性チェック（5回）
1. 再試行対象・非対象のラインが、Googleのリトライ指針（408/429/5xx/ネットワーク系＝再試行）と一致。OK。Google Cloud
2. バックオフ方式がAWS推奨の上限付き指数＋ジッターで、Retry-After優先と両立。OK。Amazon Web Services, Inc.+1
3. 再試行嵐対策としてジッター・上限回数・サーキットブレーカ・再試行予算の併用を明記。OK。sre.google+1
4. クライアント側レート制限にToken/Leaky Bucket採用の根拠を提示し、Redis等での実装方針が一般解に整合。OK。Cloudflare Docs+1
5. n8n運用（Retry on Fail/Wait）とアプリ共通クライアントの二層防御が、公式ドキュメントに沿う。OK。n8n Docs+1

必要でしたら、共通HTTPクライアントの実コード雛形（JS/TS）、Redis Token Bucket実装、**n8nテンプレ（Retry＋Wait）**をすぐにお渡しします
