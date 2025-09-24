# 00. 全体アーキテクチャ

AIコーチの全体像です。クライアント（Mobile Web）— n8nオーケストレーション — MySQLデータ層を、コアモジュールA〜Iと外部API（Symanto/Responses）で結びます。I（再試行/レート制御）は全外部呼び出しを安全にラップします。

```mermaid
flowchart TD
  subgraph Client[Client (Mobile Web)]
    UI1[IPIP-NEO-120 UI]
    UI2[Daily Chat UI]
    UI3[Intervention Card View]
  end

  subgraph Orchestrator[n8n Orchestration]
    N1[Webhook]
    N2[HTTP Request]
    N3[Function JS]
    N4[MySQL Node]
    N5[Wait/Retry]
  end

  subgraph Core[Core Modules (A–I)]
    A[A 正規化/スケール管理]
    B[B ベイズ統合]
    C[C 確信度/品質ルール]
    D[D ドリフト特徴]
    E[E 介入プランナー]
    F[F LLM後処理]
    G[G KPI集計/評価]
    H[H データ不変条件]
    I[I 再試行/レート制限]
  end

  subgraph Data[MySQL Data Layer]
    T1[(baseline_profiles)]
    T2[(ocean_timeseries)]
    T3[(intervention_plans)]
    T4[(behavior_events)]
    T5[(audit_log)]
  end

  subgraph External[External APIs]
    S1[Symanto APIs\n(Big5/CS/PT/Sentiment/Aspect)]
    OAI[OpenAI Responses]
    MOD[Moderation]
  end

  UI1 -->|IPIP回答| N1 --> A
  A -->|Baseline| H --> T1
  UI2 -->|Chat| N1 --> I --> S1
  S1 --> A --> C --> B --> D
  B -->|Posterior| T2
  D --> E
  E -->|Prompt+Tags| I --> OAI --> F --> MOD --> UI3
  F -->|Card JSON| T3
  UI3 -->|Actions| N1 --> T4
  G -->|集計| T4
  A & B & C & D & E & F --> H
  H -. constraints/roles/triggers .-> Data
  I -. wraps .-> S1
  I -. wraps .-> OAI
  F -->|Audit| T5
```

