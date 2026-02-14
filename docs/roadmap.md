# claude-crew Roadmap (v6)

25項目 + 条件トリガー3件、3フェーズ。自分用ツールとしての堅牢性・品質に集中。

> v5→v6: 公開・周知タスク除外 (40→25項目)、ロバストネス系新設、フェーズ再編。
> スタンス: OSSとして公開するが、積極的な周知・サポートはしない。Use at your own risk.

---

## 方針

- **公開目的のタスクは全て除外**: ブログ、HN/Reddit、コミュニティ形成、ユーザ向けチュートリアル等
- **残す基準**: 「自分の開発体験を直接改善するか」で判定
- **LICENSE (MIT)**: 免責条項として残す（"AS IS" で法的保護）
- **README**: セットアップリファレンス + disclaimer。マーケティング文書ではない

---

## Phase 1: v1.0 release (Week 1-2)

**Goal**: 法的要件 + エラー基盤 + 最低限のリポジトリ整備 | **Effort**: 13.5h

| # | v5# | Item | Priority | Effort | Notes |
|---|-----|------|----------|--------|-------|
| 1 | 1 | LICENSE file (MIT) | S | 0.5h | "AS IS" 免責 |
| 2 | 3 | README minimal update | A | 1h | setup手順 + disclaimer |
| 3 | 12 | Error code system (E001-E399) | S | 5h | Phase 2Bから前倒し |
| 4 | 4,5 | Error message readability + inline troubleshooting | S | 3h | 旧#4+#5統合。エラーメッセージ自体に対処法を含める |
| 5 | 13 | config.yaml validation | A | 2h | Phase 2Bから前倒し |
| 6 | 14 | execution_log.yaml error detection | A | 2h | Phase 2Bから前倒し |

**完了判定**: LICENSE存在、README disclaimer記載、E001-E399体系確立、config/exec_logバリデーション動作

---

## Phase 2: crew基盤強化 (Week 3-7)

**Goal**: ロバストネス + 拡張性 + テスト基盤 | **Effort**: 33h

### Group 1: Decomposer (2 items, 4h)
| # | v5# | Item | Priority | Effort |
|---|-----|------|----------|--------|
| 7 | 10 | scope_warning split recommendations | A | 2.5h |
| 8 | 11 | Long-running task split rules | A | 1.5h |

### Group 2: Robustness (2 items, 5h)
| # | v5# | Item | Priority | Effort | Notes |
|---|-----|------|----------|--------|-------|
| 9 | 15 | Memory MCP connection fallback | A | 1.5h | |
| 10 | - | Worker timeout detection & recovery | A | 3.5h | **新規**: Task tool timeout + parent側リトライ判定 |

### Group 3: Aggregator (1 item, 7h)
| # | v5# | Item | Priority | Effort |
|---|-----|------|----------|--------|
| 11 | 16 | Hierarchical aggregation (40+ tasks) | A | 7h |

### Group 4: Custom persona (1 item, 4h)
| # | v5# | Item | Priority | Effort | Notes |
|---|-----|------|----------|--------|-------|
| 12 | 17,18 | Custom persona examples & guide | A | 4h | 旧2項目(6h)を統合圧縮 |

### Group 5: Testing & CI (2 items, 9.5h)
| # | v5# | Item | Priority | Effort |
|---|-----|------|----------|--------|
| 13 | 19 | Integration test (minimal) | S | 7h |
| 14 | 20 | CI/CD setup | A | 2.5h |

### Group 6: Script quality (2 items, 3.5h)
| # | v5# | Item | Priority | Effort |
|---|-----|------|----------|--------|
| 15 | 21 | numbering format extension (cmd_999+) | A | 0.5h |
| 16 | 22 | new_cmd.sh UI improvements | B | 3h |

**完了判定**: Worker timeout検知動作、階層集約動作、カスタムペルソナ利用可、CI/CD稼働

---

## Phase 3: v1.1+ (feedback-driven)

**Goal**: 品質深化 + 計測 | **Effort**: 19h

### Group 1: Performance & Metrics (3 items, 8h)
| # | v5# | Item | Priority | Effort | Notes |
|---|-----|------|----------|--------|-------|
| 17 | 25 | Model selection integration | B | 4h | `/model-selection-guide` skill既存。統合のみ (v5: 7h) |
| 18 | 26 | Wave parallelism metrics | B | 2.5h | |
| 19 | - | execution_log analysis tool | B | 1.5h | **新規**: cmd履歴サマリ。analyze_patterns.sh拡張 |

### Group 2: Test expansion (3 items, 11h)
| # | v5# | Item | Priority | Effort |
|---|-----|------|----------|--------|
| 20 | 31 | Integration test (Round 2-7 verification) | A | 6h |
| 21 | 32 | Edge case tests | B | 2h |
| 22 | 39 | Test coverage report | B | 3h |

**完了判定**: 検証スイート動作、performance metrics取得可

---

## 条件トリガー (時期未定)

| # | v5# | Item | Trigger | Effort |
|---|-----|------|---------|--------|
| 23 | 23 | LP settling timing optimization | LP entity >= 20 | 1.5h |
| 24 | 24 | LP confidence scoring | LP entity >= 20 | 1.5h |
| 25 | - | Phase 1.5 再有効化 | 四半期3回以上のplan失敗 | 0h (config変更) |

---

## スケジュール

| Week | Phase | Focus | Effort |
|------|-------|-------|--------|
| 1-2 | Phase 1 | v1.0 release | 13.5h |
| 3-7 | Phase 2 | crew基盤強化 | 33h |
| Post-7 | Phase 3 | v1.1+ (feedback-driven) | 19h |
| - | Triggers | 条件成立時 | 3h |

**Total**: 68.5h

---

## 完了判定基準

- **v1.0**: LICENSE, README disclaimer, Error code system, config/exec_log validation
- **v1.0.x**: Worker timeout, 階層集約, カスタムペルソナ, CI/CD
- **v1.1+**: Performance metrics, Test expansion

---

## 依存関係

```
#3 (error code) → #4 (error message) → Phase 2開始
#13 (integration test) → #14 (CI/CD)
LP entity >= 20 → #23, #24
```

グループ内は並列実行可。Phase間は直列。

---

## 優先度ランク定義

| Rank | 意味 | 例 |
|------|------|-----|
| S | 自分の開発ワークフローをブロック / 法的要件 | LICENSE, Error code system |
| A | 日常のcrew利用を大幅改善 | Worker timeout, CI/CD |
| B | あると便利、時間があれば | Wave metrics, UI改善 |
| C | 条件トリガー専用 | LP tuning (entity >= 20) |

---

## v5→v6 変更履歴

### Mutation一覧（8種）

| # | Mutation | Impact |
|---|----------|--------|
| 1 | **Phase 2A完全廃止** | Use case/Examples/Tutorial/CONTRIBUTING除外 |
| 2 | **Error系Phase 1前倒し** | v5 #12,#13,#14をPhase 2B→1に移動。Critical path短縮 |
| 3 | **Troubleshooting→Inline化** | 独立ドキュメント→エラーメッセージに統合 (5h→3h) |
| 4 | **Custom persona統合** | 2項目→1項目 (6h→4h) |
| 5 | **条件トリガー分離** | LP系+Phase 1.5をフェーズから独立 |
| 6 | **Robustness group新設** | Worker timeout検知を新規追加 |
| 7 | **Model selection圧縮** | 既存Skill活用 (7h→4h) |
| 8 | **テスト戦略整理** | Phase 2=基盤、Phase 3=拡張の2段構成 |

### 除外項目（17項目）

| v5# | Item | 理由 |
|------|------|------|
| 2 | FAQ | 外部ユーザ向け |
| 5 | Troubleshooting guide | #4に統合 |
| 6 | Use case collection | マーケティング |
| 7 | Examples repository | 外部ユーザ向け |
| 8 | First-run tutorial | 外部ユーザ向け |
| 9 | CONTRIBUTING.md | コミュニティ前提 |
| 27 | GitHub Discussions | コミュニティ運営 |
| 28 | Launch blog post | マーケティング |
| 29 | HN/Reddit preparation | マーケティング |
| 30 | Claude Code official contact | パートナーシップ |
| 33 | Documentation adjustments | 外部ドキュメント前提 |
| 34 | Reference consistency | CI lintで代替可 |
| 35 | v1.1 roadmap document | 本文書で管理 |
| 36 | Developer onboarding | 外部開発者向け |
| 37 | Best practices guide | 外部開発者向け |
| 38 | Quick Start validation | Integration testに統合 |
| 40 | TESTING.md | README sectionで代替 |
