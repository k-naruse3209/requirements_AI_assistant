# D. ドリフト/トレンド検知の時系列特徴量 

D. ドリフト/トレンド検知の時系列特徴量とは？

一言で：日々更新される OCEAN_hat（B.ベイズ統合の出力） の“動き”を、
* ①EWMA（指数加重移動平均）,
* ②傾き（slope：直近ウィンドウの線形トレンド）,
* ③ローリング分散（変動の大きさ） といった軽量な指標で捉え、必要に応じて **変化点検知（CUSUM／Page–Hinkley／Bayesian など）**も補助的に使い、小さなズレや緩やかなドリフトを早めに察知する仕組みです。 EWMAは「新しい観測ほど重みを大きくする」平均で、小さな変化に敏感です（重みλの選び方で感度を調整）itl.nist.gov+1。傾きは「直線回帰の係数」を見る基本の方法で、増減の向きと強さを数値化しますウィキペディア。分散は“散らばり”＝安定度の目安です。
何のため？
* ダッシュボードに「短期の動き」をわかりやすく出す
* 図3（介入プランナー）で「最近不安定なら優しく」「上向きなので一歩踏み込む」といった強度調整に使う
* 変化点シグナルが出たら「目標/プロンプトの切替」などの運用フックに使う（任意）

どのシステムとどう連携？
* 入力（from B）：各因子（O,C,E,A,N）の Posterior（Tと0–1の両系統）＋Posterior分散
* 本モジュール（D）：
    * 因子ごとに EWMA、slope、ローリング分散 を計算
    * （任意）変化点検知：CUSUM（小さな平均シフトに強い）、Page–Hinkley（平均の急変を監視）、Bayesian Online（直近のラン長分布）などで補助判定 itl.nist.gov+2GeeksforGeeks+2
* 出力（to 図3/ダッシュボード）：
    * ewma_λ, slope_Nd, var_Nd（因子別）＋（任意）cusum_flag / ph_flag / bocpd_p
    * しきい値越え時のイベント（例：trend_up_strong）

どう作る？（実装ガイド）
1) 指標の定義
① EWMA（指数加重移動平均）
* 再帰式：EWMA_t = λ·Y_t + (1-λ)·EWMA_{t-1}（0<λ≤1）itl.nist.gov
* λは0.15〜0.3が小さな変化に敏感でよく使われます（NIST/Hunterの推奨帯）itl.nist.gov+1。
* 直感：λ↑ → 新しいデータを重視（感度↑・誤警報↑）。λ↓ → ノイズに強いが反応が遅い。
* ※Holt–Winters等の指数平滑も“最近を重く”の一族（平滑＋予測系）。必要なら将来拡張で採用可 otexts.com+1。
② 傾き（slope）
* 直近N日の 単回帰の傾き β̂ を指標化（N=7や14が扱いやすい）ウィキペディア。
* 外れ値に強い版として Theil–Sen（中央値傾き） も候補（ロバスト）ウィキペディア。
③ ローリング分散
* 直近N日の分散を安定に計算（桁落ち回避のため、Welford系などの数値安定アルゴリズム推奨）ウィキペディア。
* 分散↑＝不安定化、分散↓＝安定化のシグナル。
（任意）変化点検知
* CUSUM：小さな平均シフトを累積和で検出（Shewhartより微小変化に強い）itl.nist.gov
* Page–Hinkley：平均の急変をしきい値で検出（ストリームのドリフト検知で広く使われる）GeeksforGeeks
* Bayesian Online Change Point Detection（BOCPD）：直近の「ラン長」の確率をオンラインで更新して変化点を推定 arXiv
* ADWIN：可変長ウィンドウで分布変化を検知（数学的保証あり）Riverml
運用の現実解：まずは EWMA＋slope＋分散 をダッシュボードに出し、しきい値やランルール（例：±3σ）でアラート。次に必要に応じて CUSUM/PH/BOCPD/ADWIN を追加採用します。3σ系ルールはSPCの基本で、±3σを越えたら要注意（Shewhart、ARL等の指標あり）itl.nist.gov+1。
2) しきい値の決め方（実務）
* 基準期間（安定とみなす期間）で 平均μ・標準偏差σ を推定
* Shewhart流の3σを基本線（誤警報率の目安が知られている）itl.nist.gov
* EWMAの制御限界は λ に依存（解析式あり、L=3を使う例が多い）ウィキペディア
* 誤警報が多ければ λ↓ or L↑、鈍ければ λ↑ or L↓。シミュレーションで**ARL（平均発報間隔）**を合わせ込むのが安全ですitl.nist.gov。
3) I/O スキーマ例（1ユーザ×因子ごと、Tスコア系）
入力（B→D）

```json
{
  "user_id": 123,
  "series_T": [52, 53, 51, 54, 55, 56, ...],
  "ts": ["2025-09-01", "..."],
  "lambda": 0.2,
  "win_trend_days": 7,
  "win_var_days": 14
}```
出力（D→ダッシュボード/図3）

```json
{
  "ewma_T": 54.1,
  "slope_T_7d": +0.42,
  "var_T_14d": 6.8,
  "flags": ["trend_up"],             // or ["stable","volatility_high"]
  "optional": { "cusum_flag": false, "ph_flag": false }
}```
4) 擬似コード（n8nのFunctionノード想定／因子ごとに実行）

```js
// EWMA
function ewma(arr, lambda){
  let z = arr[0];
  for (let i=1; i<arr.length; i++) z = lambda*arr[i] + (1-lambda)*z;
  return z; // NISTの定義式どおり
}

// 直近N日の単回帰Slope（y ~ a + b*t）
function slope_lastN(arr, N){
  const y = arr.slice(-N);
  const n = y.length;
  let sx=0, sy=0, sxx=0, sxy=0;
  for (let i=0; i<n; i++){ const x=i+1; sx+=x; sy+=y[i]; sxx+=x*x; sxy+=x*y[i]; }
  const denom = n*sxx - sx*sx;
  return denom===0 ? 0 : (n*sxy - sx*sy)/denom; // OLSの傾き β̂
}

// 数値安定なローリング分散（単純実装例）
// 実装ではWelford系などの安定アルゴリズム推奨
function rollingVar_lastN(arr, N){
  const a = arr.slice(-N);
  const n = a.length;
  const mean = a.reduce((p,c)=>p+c,0)/n;
  const s2   = a.reduce((p,c)=>p+(c-mean)*(c-mean),0)/(n-1);
  return s2;
}

// 本体
const λ = $json.lambda || 0.2;
const slopeWin = $json.win_trend_days || 7;
const varWin   = $json.win_var_days   || 14;
const yT = $json.series_T;
const out = {
  ewma_T: ewma(yT, λ),
  slope_T_7d: slope_lastN(yT, slopeWin),
  var_T_14d: rollingVar_lastN(yT, varWin)
};
// ランルール例：3σ超でフラグ
// μ, σ は基準期間から推定してキャッシュしておく
return out;
```
参考：EWMAの定義とλのガイダンス（0.15〜0.3が一般的）itl.nist.gov+1、OLSの傾き定義ウィキペディア、分散の安定計算法（Welford等）ウィキペディア、CUSUM/PH/BOCPDの位置づけitl.nist.gov+2GeeksforGeeks+2。

受け入れ基準（例）
1. EWMAが仕様どおり z_t = λ·y_t + (1-λ)·z_{t-1} を満たし、λの変更で感度が変わる（再現テスト）itl.nist.gov
2. 傾きは直近N日のOLSで算出し、単調増加系列で正, 単調減少系列で負になる（サンプルテスト）ウィキペディア
3. ローリング分散はWelford等の数値安定法で誤差が小さい（比較テスト）ウィキペディア
4. 3σ系のしきい値で誤警報率（ARL）が設計値に近い（シミュレーション）itl.nist.gov
5. （任意）変化点検知をONにすると、合成データの平均シフト（小/中）をCUSUM/EWMAが検出、急変をPage–Hinkleyが検出、直近ラン長の変化をBOCPDが確率で示す（ユニットテスト）itl.nist.gov+2GeeksforGeeks+2

よくある質問（実装の勘どころ）
* λはいくつにすべき？ まず 0.2 前後から。小さなドリフト検知には相性が良いという実務ガイドが多数あります（0.15〜0.3帯）itl.nist.gov+1。
* 季節性（曜日/週末）で誤検知が増える STL分解でトレンドと季節を分離してからEWMA/傾きを当てると改善します（StatsmodelsのSTLなど）statsmodels.org+1。
* 直近N日を7にする意味 週のリズムを見る最小単位。14/28日に増やすと頑健になるが反応が遅くなる（EWMAのλと合わせてチューニング）。
* 高度化の余地 Holt–Winters（ETS）でレベル・トレンド・季節を同時推定する強化案もあります（将来拡張）otexts.com+1。

整合性チェック（5回）
1. 前段との整合：BのPosterior（T & 0–1）をそのまま入力にし、Dは計算専用で元値を書き換えない（参照）。OK。
2. 単位の一貫性：ダッシュボードは人向けの T、アルゴリズム判断は Tでも0–1でも定義可（式は同形）。OK。
3. 理論と式の一致：EWMAの定義、OLS傾き、分散の安定計算法、SPCの3σルールを一次情報で確認済み。OK。itl.nist.gov+3itl.nist.gov+3ウィキペディア+3
4. 誤警報対策：λ/L/ウィンドウ長のチューニング、季節分解（STL）、ARLでの妥当性確認を手順化。OK。statsmodels.org+1
5. 拡張互換性：CUSUM/PH/BOCPD/ADWINは補助扱いで、基礎3指標（EWMA/傾き/分散）と矛盾せず段階導入できる。OK。Riverml+3itl.nist.gov+3GeeksforGeeks+3

必要でしたら、このDモジュールのn8n Function用JS、MySQLテーブル設計（ocean_features）、**シミュレーションノート（ARL/λ・L・Nの感度分析）**まで即時にお渡しできます。
