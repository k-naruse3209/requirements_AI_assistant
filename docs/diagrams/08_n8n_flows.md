# 08. n8nフロー雛形（3本）

MVP構成の3フロー（Onboarding / Measure / Plan）のノード構成サマリです。HTTP呼び出しはIの方針（指数バックオフ/Retry-After）で設定し、DB書き込みは専用ロールのみ許可します。

```mermaid
flowchart LR
  subgraph Onboarding
    OW[Webhook] --> OF[Function:採点/正規化(A)]
    OF --> OM[MySQL: baseline_profiles]
  end

  subgraph Measure(Daily)
    MW[Webhook] --> MT[HTTP:Symanto]
    MT --> MF[Function:正規化(A)/確信度(C)/ベイズ(B)]
    MF --> MM[MySQL: ocean_timeseries]
    MM --> MD[Function:特徴(D)]
  end

  subgraph Plan(Intervention)
    PW[Cron/Webhook] --> PF[Function:E プランナー]
    PF --> PO[HTTP:OpenAI]
    PO --> PP[Function:F 後処理]
    PP --> PM[MySQL: plans/audit]
    PP --> PN[通知配信]
  end
```

