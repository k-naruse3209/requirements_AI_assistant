# 02. 日次測定パイプライン

チャット入力→言語判定/翻訳→Symanto分析→Aで0–1/Tへ整列→Cで観測分散σx²/品質フラグ→BでPrior×Likelihoodの精度重み付け→T/0–1のPosteriorを`ocean_timeseries`に追記→DでEWMA/傾き/分散を算出。

```mermaid
flowchart TD
  Chat[Daily Chat] --> N1[n8n Webhook]
  N1 --> L[Lang detect/Translate]
  L --> I1[I (Retry/Rate)]
  I1 --> S1[Symanto Big5/CS/PT/Sentiment/Aspect]
  S1 --> A[A 正規化(0–1/T揃え)]
  A --> C[C 確信度/品質: σx² & flags]
  C --> B[B ベイズ統合]
  B --> T2[(ocean_timeseries)]
  B --> D[D EWMA/傾き/分散]
  D --> Dash[Dashboard/Planner参照]
```

