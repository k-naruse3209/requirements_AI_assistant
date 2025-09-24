# E. 介入プランナー（JITAIの中核） 

これは何をするシステム？
ひとことで言うと、**「その人に・その時に・その量だけ」**最適な介入（例：CBT、WOOP/MCII、If–Thenプラン）を選び、LLMに渡す具体的な指示（プロンプト仕様）を決める意思決定エンジンです。この“その人・その時・その量”という設計思想こそ JITAI = Just-in-Time Adaptive Intervention の定義で、個人の状態変化に合わせて介入の種類・タイミング・強度を調整します。PubMed+1
介入の中身は科学的な行動変容技法から選びます。たとえばIf–Then（実行意図）は目標達成を促進する強力な手法で大きめの効果量が示されていますし、WOOP/MCIIは願望→結果→障害→計画の順で自己調整を高めます。PubMed+3サイエンスダイレクト+3がん対策の部門+3 気分や認知に働きかけるCBTの原理も、短いマイクロ介入として広く用いられています。APA+1

他システムとの連携（どこから何を受け取り、どこへ渡す？）

A: スコア整形・正規化
        │（OCEAN：T / 0–1）
B: ベイズ統合（Posterior = OCEAN_hat, 分散）
        │
C: 確信度 & 品質ルール（観測分散、品質フラグ）
        │
D: 時系列特徴（EWMA / 傾き / 分散 / 変化点）
        │
E: 介入プランナー  ←（CS/PT, Sentiment, Aspect も同一発話から）
        │  ├─ 選んだ技法・トーン・長さ・CTA
        │  └─ LLM用プロンプト仕様
        ▼
OpenAI Responses API で介入カード生成 → 配信・ログ
* 上流からの入力
    * OCEAN_hat とその分散（B）＝“いまの性格推定”と不確実性
    * 確信度・品質フラグ（C）＝“今日の観測の信頼度”
    * 時系列特徴（D）＝EWMA（短期平均）、傾き（上向き/下向き）、分散（安定/不安定）
    * CS/PT / Sentiment / Aspect＝同一発話の語り口・特性・感情・話題（SymantoのAPI群）Symanto - Psychology AI+1
* 下流への出力
    * 介入方針（例：technique=WOOP, tone=encouraging, length=short, cta=具体的If–Then）
    * LLMプロンプト（Responses API で自然文カード生成）OpenAI Platform+2Microsoft Learn+2
    * 選定根拠ログ（入力特徴→スコア→採択の連鎖）

どう作る？（設計 → ルール版 → 学習版）
1) 介入カタログ（最小セット）
* CBT：自動思考の同定→再評価→行動実験（超要約の1～3ステップ）。APA
* WOOP/MCII：願望→最高結果→主障害→If–Then計画。サイエンスダイレクト+1
* If–Then：状況Sに出会ったら行動Bをする、の形で実行意図を固定。サイエンスダイレクト
すべてトーン（やさしい/フラット/チャレンジング）と長さ（短/中/長）をパラメタ化してLLMに渡せるように定義。
2) ルールベース版（MVP）
各介入に方策スコアを付け、最大を選びます（同点はソフトマックス抽選）。
* スコア関数の例（0〜1スケールの特徴量を想定）
    * score_CBT = a1*NegSent + a2*HighN + a3*Volatility + a4*RuminationAspect
    * score_WOOP = b1*GoalTopic + b2*HighC + b3*SlopeUp + b4*ObstacleAspect
    * score_IFTH = c1*Actionability + c2*LowN + c3*HighC + c4*TimeCueDetected
* 安全・品質ルール
    * Cからの確信度が低い/品質フラグが立っている日は短め＋穏当トーンを強制
    * BのPosterior分散が高いときは“リマインド型”に抑える
    * DのEWMAが大きく下落かつ分散↑のときはサポート寄りCBTを優先
疑似コード（簡略）

function plan(inputs){
  const f = featuresFrom(inputs); // Sentiment, Aspect, OCEAN_hat, EWMA, slope, var, CS/PT...
  const sCBT  = dot([NegSent, HighN, Volatility, Rumination], a);
  const sWOOP = dot([GoalTopic, HighC, SlopeUp, Obstacle], b);
  const sIF   = dot([Actionability, LowN, HighC, TimeCue], c);

  let choice = argmax({CBT:sCBT, WOOP:sWOOP, IFTHEN:sIF});

  // 品質ルール
  if (inputs.confidence < 0.4 || inputs.quality_flags.length) {
    choice.tone = "gentle"; choice.length = "short";
  } else {
    choice.tone = chooseToneByCS(f.CS); // 例：合理⇔情緒で切替
    choice.length = "short_or_medium";
  }
  return choice;
}
3) 学習版（オンライン最適化）
コンテキスト付きバンディットで、ユーザー文脈（OCEAN_hat、Sentiment、CS/PT、傾き等）を使いながら、**探索（試す）と活用（効く方を使う）**を両立して方策を自動最適化できます。代表的なのは LinUCB や Thompson sampling。大規模パーソナライズで実績があります。Stanford University+4arXiv+4arXiv+4
* 報酬の定義：翌日の実行（クリック/実施チェック）、継続日数、自己評価など
* 安全探索：確信度やPosterior分散に応じたクリップ（介入強度の上限）
* オフライン評価：ログのランダム化配信部分で逆傾向重み付け（IPS）やオフラインポリシー評価を実施（Li+10 はニュースで検証）。arXiv

LLMへの受け渡し（Responses API）
選んだtechnique/tone/length/CTAと根拠タグを、OpenAI Responses APIの/responsesに渡してカード文面を生成します（Assistantsの後継API。エージェント構築向けの統合機能）。OpenAI Platform+2ザ・ヴァージ+2
プロンプト仕様（例）

{
  "technique": "WOOP",
  "tone": "encouraging",
  "length": "short",
  "persona": {"O":0.62,"C":0.48,"E":0.55,"A":0.60,"N":0.35},
  "today": {"sentiment":"negative","aspects":["仕事:疲労","睡眠:不足"]},
  "trend": {"ewma_delta":"-1.2","slope_7d":"-0.3","var_14d":"high"},
  "cta": "今夜22時に10分だけ準備するIf–Thenを作る",
  "explain_tags": ["why:neg_mood_support","match:CS_emotional","safety:gentle"]
}

I/Oスキーマ（Eモジュール）
入力

{
  "user_id": 123,
  "ocean_hat": {"O":0.62,"C":0.48,"E":0.55,"A":0.60,"N":0.35},
  "posterior_var": {"O":0.08,"C":0.10,"E":0.09,"A":0.07,"N":0.11},
  "confidence": 0.73,
  "quality_flags": [],
  "features": {
    "sentiment":"negative",
    "aspects":["仕事","睡眠"],
    "cs":"emotional", "pt":"value_oriented",
    "ewma": {"N":41.5}, "slope_7d":{"C":+0.2}, "var_14d":{"N":"high"}
  }
}
出力

{
  "plan": {
    "technique": "WOOP",
    "tone": "encouraging",
    "length": "short",
    "cta": "22:00になったら10分だけ資料に手を付ける",
    "llm_prompt": "...（Responses APIに渡す文字列）...",
    "rationale": {
      "score": {"CBT":0.42,"WOOP":0.55,"IFTHEN":0.48},
      "evidence_tags": ["neg_sent","goal_topic","slope_up_C_low"]
    }
  }
}

受け入れ基準（例）
1. 同一入力に対して決定論的に同一プランを返す（学習OFF時）。
2. 品質フラグON/確信度低のとき、トーン=gentle & 長さ=shortになる。
3. Dのslopeが正かつ分散低のとき、攻め度合いが一段上がる（例：If–Then/チャレンジトーン）。
4. 学習ON（バンディット）時、報酬の移動平均がベースラインより有意に向上（オフライン検証→パイロットA/B）。arXiv
5. LLM出力はResponses APIで生成し、選定根拠タグをログに保存できる。OpenAI Platform

初心者向けの作り方・手順（実装ロードマップ）
1. 特徴量の整列：B/C/DとSymantoの出力を Function ノード（またはサービ ス）で整理（OCEAN_hat、確信度、EWMA/傾き/分散、Sentiment/Aspect、CS/PT）。Symanto - Psychology AI+1
2. ルール版の方策スコアを実装 → argmaxで選択 → 品質ルールでトーン/長さを最終調整。
3. Responses APIを呼び出す I/O を整備（テンプレ化／フォールバックも用意）。OpenAI Platform+1
4. ログ設計：inputs → scores → choice → prompt → user_feedback（報酬） をすべて保存。
5. 学習版（任意）：LinUCB または Thompson samplingで探索と活用をバランス。最初は**保守的探索（ε小、事前分散大きめ）**から。arXiv+1
6. 評価：オフライン（逆傾向重み付け）→ 小規模A/B → 本番。arXiv

よくある質問（FAQ）
* WOOPとIf–Thenは何が違う？ WOOPは目標→結果→障害→計画の順で“心理的対比”を行い、その最後で実行意図（If–Then）を作る体系。つまりWOOP ⊃ If–Thenの関係です。サイエンスダイレクト
* CS/PTは本当に使えるの？ SymantoはCommunication StyleやPersonality TraitsのAPIを公開しており、合理/情緒的などの語り口合わせに使えます（トーン選択に有用）。Symanto - Psychology AI+1
* JITAIって要は“タイミング通知”だけ？ いいえ。種類・量・タイミングの3点を個人と状況に合わせて適応させる設計全体がJITAIです。PubMed

整合性チェック（5回）
1. JITAIの原則（“right type/amount/time for the individual”）に沿って、Eが種類・強度・タイミングを決め、A～Dと整合している。OK。PubMed
2. 技法の根拠：If–Then（実行意図）のメタ分析エビデンス、WOOP/MCIIのRCT、CBTの有効性を参照。OK。APA+4サイエンスダイレクト+4がん対策の部門+4
3. 学習最適化：コンテキスト付きバンディット（LinUCB/Thompson）で探索と活用を設計可能。OK。arXiv+1
4. 実装の現実性：SymantoのCS/PTでトーン合わせ、OpenAI Responses APIで文面生成という具体的API連携を明示。OK。Symanto - Psychology AI+2symanto-research.github.io+2
5. 安全策：Cの確信度とBの分散で強度をクリップ、品質フラグで短く穏やかにフォールバックするポリシーを記述。OK。

必要であれば、このプランナーをルール版（MVP）の実コードと学習版（LinUCB/Thompson）の雛形、Responses APIプロンプト集に落としてお渡しします。
