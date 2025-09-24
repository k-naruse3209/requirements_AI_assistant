# 07. KPI集計と評価（G）

配信/行動ログから実行率・Streak・Retention等を日次集計し、週次でコホート/CI/EWMAを更新。A/BはCUPED等で分散削減しつつ効果量（Cohen’s d）とCIでレポートします。

```mermaid
flowchart TD
  BE[(behavior_events)] --> G1[G KPIジョブ: 日次]
  IP[(intervention_plans)] --> G1
  G1 --> KD[(kpi_daily)]
  KD --> G2[週次: Cohort/Retention/EWMA]
  G2 --> KC[(kpi_cohorts)]
  KD --> EXP[実験評価(A/B + CUPED)]
  EXP --> REP[レポート/ダッシュボード]
```

