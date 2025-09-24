# AI Assistant Specifications (Updated 2025-09-16)

このディレクトリには、AIコーチシステムの最新仕様書とアーキテクチャ図が含まれています。

## 参照場所（図・仕様）

### docs/specification/
図・仕様PDFはすべて本ディレクトリ配下にあります。
- `all_architecture_diagram_v2025-09-16.pdf` — 全体アーキテクチャ概要図
- `onboarding_baseline_flow_v2025-09-16.pdf` — 図1: オンボーディングとベースライン確立
- `daily_measurement_pipeline_v2025-09-16.pdf` — 図2: 日次測定パイプライン
- `intervention_engagement_flow_v2025-09-16.pdf` — 図3: 介入とエンゲージメント
- `specification_v3.0.pdf` — 詳細な要件定義書と機能設計書

### docs/diagrams/
Mermaidで作成した開発者向けの分割図面は以下を参照してください。
- `docs/diagrams/README.md` — 図面インデックス

## システム概要

### 主要コンポーネント
- **クライアント**: Mobile Web (IPIP-NEO-120チャットUI)
- **オーケストレーション**: n8nワークフロー群
- **データ層**: MySQL (Baseline Store, OCEAN時系列, KPIログ)
- **外部API**:
  - Symanto API群 (Big Five, Communication Style, Personality Traits, Sentiment, Aspect-based)
  - LLM Responses API

### 主要フロー
1. **オンボーディング**: IPIP-NEO-120 (120項目) → Baseline確立 → handoff
2. **日次測定**: チャット入力 → 言語判定/翻訳 → Symanto分析 → OCEAN更新 → handoff
3. **介入**: 発話解析 → CBT/WOOP/If-Then選択 → LLM自然文生成 → 通知・記録

### 技術仕様
- **心理学理論**: Big Five (OCEAN)モデル、JITAI思想
- **介入手法**: CBT、WOOP、Implementation Intentions (If-Then)
- **データ統合**: ベイズ統合によるPrior (IPIP) + Likelihood (テキスト)

## 更新履歴
- 2025-09-16: 最新仕様書v3.0と詳細フロー図を追加
