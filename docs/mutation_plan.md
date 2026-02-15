# Mutation Mechanism — Implementation Plan

**Version**: 1.0
**Date**: 2026-02-15
**Origin**: cmd_079–088 (10-round iterative design)
**Status**: Layer 0 deployed, Layer 1–2B conditional

---

## Background

claude-crewの反復的改善ループ（refine-iteratively等）において、局所最適に陥る問題を解決するための「mutation（突然変異）」メカニズム。10ラウンドの設計反復を経て、以下の知見から4層ハイブリッドアーキテクチャに収束した:

- 19タスクの大規模フレームワーク（68-95時間）は過剰設計 → 却下
- 単純なプロンプト注入（14行）で70-80%の価値を達成可能
- path-passing制約下では矛盾する出力の自動統合が不可能（Attack #3）
- 既存のレビューフェーズを強化することでAttack #3を回避可能

---

## Architecture: 4-Layer Hybrid

```
Layer 0: Self-Challenge Prompt ──── 常時ON、全タスク適用
Layer 1: Mutation Keywords ──────── ユーザー指定、request.mdにキーワード記載
Layer 2A: Enhanced Reviewer ─────── 自動、複雑タスクに適用
Layer 2B: /mutate Skill ─────────── オンデマンド、ユーザー手動呼び出し
```

| Layer | メカニズム | トリガー | 実装コスト | 品質カバレッジ |
|-------|-----------|---------|-----------|--------------|
| **0** | config.yamlのSelf-Challengeプロンプト | 常時ON | 1時間 | 70-80% |
| **1** | request.mdのmutationキーワード→decomposerが解釈 | ユーザー指定 | +3-4時間 | 75-85% |
| **2A** | worker_reviewer.mdのRed Pen Protocol | 自動（複雑タスク） | +2-4時間 | 70-85% |
| **2B** | `/mutate`スキル（専用mutationワーカー） | ユーザー手動 | +25-30時間 | 85-90% |

**設計原則**: シンプルな解決策から始め（Layer 0で70-80%）、実測値に基づいてのみ次層に進む（progressive validation）。

---

## Layer Details

### Layer 0: Self-Challenge Prompt (DEPLOYED)

**変更ファイル**:
- `config.yaml` — `phase_instructions.execute`に14行のSelf-Challengeプロンプト追加
- `templates/worker_common.md` — Self-Challenge Output Formatセクション追加

**動作**: 全ワーカーが結果に`## Self-Challenge`セクションを含める。

| タスク種別 | 要求される出力 |
|-----------|--------------|
| Trivial (<10分) | Failure Scenarios 2件のみ |
| Complex (≥3設計選択肢 or 新規領域) | 全サブセクション（Assumption Reversal, Alternative Paradigm, Pre-Mortem, Evidence Audit） |

**Anti-sycophancy対策**:
- `MUST contradict ≥1 baseline claim` — 最低1つのベースライン矛盾を義務化
- BAD/GOOD例を明示 — 追従的出力と真の批判的出力の違いを示す
- RE-CHALLENGE指示 — 全指摘がベースラインに同意した場合、やり直しを強制

**限界**: プロンプトエンジニアリングの構造的上限（70-80%）。マルチウェーブタスク（60%失敗）、新規ドメイン（80%失敗）、パラダイムレベルの挑戦（70%失敗）には不十分。

### Layer 1: Mutation Keyword Detection

**変更ファイル**: `templates/decomposer.md`

**動作**: request.mdに含まれるキーワードをdecomposerが検出し、タスクファイルに戦略固有の指示を注入。

| キーワード | 戦略 | ワーカーへの指示 |
|-----------|------|---------------|
| "challenge assumptions" | assumption_reversal | 3-5の前提を特定し、各々FALSEである理由を論証 |
| "find flaws" / "red team" | adversarial_review | 5つの失敗モードをリスト化、リスク順にランク付け |
| "explore alternatives" | alternative_exploration | ベースラインと矛盾する3つの代替案を提案、トレードオフ比較 |
| "critical challenges" | comprehensive_mutation | 上記3戦略すべてを適用 |

**Layer 0との関係**: 補完的。選択されたタスクはLayer 0（ベースライン自己チェック）とLayer 1（戦略固有の深い突然変異）の両方を受ける。

### Layer 2A: Enhanced Reviewer (Red Pen Protocol)

**変更ファイル**:
- `templates/worker_reviewer.md` — Red Pen Review Protocolセクション追加
- `templates/decomposer.md` — depthフィールド（standard/adversarial）の追加

**動作**: decomposerが複雑タスクのレビューに`depth: adversarial`を設定。レビュワーがRed Pen Protocolを適用し、verdict（approve/revise/reject）を出力。verdictはaggregatorに流れる。

**Red Pen Protocol**:
1. Assumption Audit — 3-5の前提を監査
2. Failure Mode Catalog — 5つの失敗モード（技術/セキュリティ/UX/運用/統合）
3. Pre-Mortem — 「6ヶ月後に壊滅的に失敗した。根本原因は？」
4. Evidence Audit — 実証データのない主張をフラグ
5. Alternative Check — ベースラインパラダイムと矛盾する根本的に異なるアプローチ

**Attack #3解決**: verdictがaggregatorに統合されるため、親セッションによる手動統合不要。path-passing制約を維持したまま矛盾を処理可能。

**弱点**: sycophancy率15-20%（同一ワーカーが構築+レビュー→認知的不協和）。セキュリティ監査レベルの厳密さには不十分。

### Layer 2B: /mutate Skill

**新規ファイル**:
- `.claude/skills/mutate/SKILL.md` — スキル定義
- `templates/mutation_instructions.md` — 5戦略のワーカープロンプト
- `.claude/skills/mutate/mutation_defaults.yaml` — 設定

**呼び出し**:
```bash
/mutate <artifact_path>                                    # 自動戦略選択
/mutate <artifact_path> --strategy=adversarial_review      # 戦略指定
/mutate <artifact_path> --compare                          # 比較モード
/mutate <artifact_path> --rounds=3                         # マルチラウンド
```

**5戦略**: assumption_reversal, adversarial_review, alternative_exploration, failure_mode_analysis, paradigm_challenge

**Validation Gate**: `contradicts_baseline: false`の場合、出力をリジェクト。

**Attack #3への対処**: 別出力トラック（`mutation_report.md`）。ユーザーが手動で`aggregated.md`と統合。

**強み**: sycophancy率10%（専用ワーカー、認知的不協和なし）。外部アーティファクトのmutationも可能。

---

## Decision Framework

```
タスク開始 → Layer 0 自動適用
  │
  ├─ Trivialタスク → Layer 0のみ (20-30%)
  │
  ├─ 通常タスク → Layer 0 + Layer 2A自動 (70-85%)
  │
  ├─ 複雑タスク + キーワード指定 → Layer 0 + 1 + 2A (75-85%)
  │
  └─ 超高リスクタスク → Layer 0 + 1 + 2A + /mutate手動 (85-90%)
```

| タスク例 | 推奨レイヤー | ユーザーアクション |
|---------|------------|-----------------|
| typo修正 | L0 | なし |
| APIエンドポイント設計 | L0 + L2A | なし |
| キャッシュ層設計 | L0 + L1 + L2A | requestに"challenge assumptions"追加 |
| 認証システム設計 | L0 + L1 + L2A + L2B | キーワード追加 + `/mutate`呼び出し |
| セキュリティアーキテクチャ | L0 + L1 + L2A + L2B | キーワード追加 + `/mutate --strategy=adversarial_review --depth=deep` |

---

## Implementation Roadmap

### Phase 1: Layer 0 Deploy (Week 1) — DONE

- [x] `config.yaml` — `phase_instructions.execute`編集
- [x] `templates/worker_common.md` — Self-Challenge Output Format追加
- [x] commit: `c8d340b`

### Phase 2: Layer 0 Measurement (Week 2-3) — NEXT

10タスク（trivial 3, medium 4, complex 3）を実行し、以下を計測:

| 指標 | 目標 | Kill基準 |
|-----|------|---------|
| Compliance Rate | ≥65% | <50% |
| Genuine Critique Rate | ≥60% | sycophancy >40% |
| User Value Rate | ≥50% | delta <+5% |

**判定**:
- mutation value ≥60% → **STOP**（Layer 0で十分、30-39時間節約）
- 30-60% → **PROCEED** to Layer 1
- <30% or compliance <50% or sycophancy >40% → **KILL**（Layer 0無効化）

### Phase 3: Layer 1 Deploy (Week 4, conditional)

- [ ] `templates/decomposer.md` — Mutation Keyword Detectionセクション追加
- [ ] キーワード付きrequest 2件でテスト
- [ ] ワーカー出力にLayer 0 + Layer 1セクションが含まれることを確認

**判定**: keyword adoption ≥30%, mutation value ≥60% → STOP

### Phase 4: Layer 2A Deploy (Week 6, conditional)

- [ ] `templates/worker_reviewer.md` — Red Pen Review Protocolセクション追加
- [ ] `templates/decomposer.md` — depthフィールドロジック追加
- [ ] 複雑タスク3件でテスト
- [ ] verdictがaggregatorに流れることを確認

**判定**: false positive rate <30%, combined value ≥85% → Layer 2B optional

### Phase 5: Layer 2B Implement (Week 7-9, conditional)

- [ ] `.claude/skills/mutate/SKILL.md` 作成
- [ ] `templates/mutation_instructions.md` 作成
- [ ] `.claude/skills/mutate/mutation_defaults.yaml` 作成
- [ ] 統合テスト3シナリオ

**判定**: invocation rate ≥20%, user value ≥50%

### Phase 6: Hybrid Validation (Week 10-11, conditional)

- [ ] ルーティンタスク5件 (L0+L2A)
- [ ] 高リスクタスク3件 (L0+L1+L2A+L2B)
- [ ] ユーザー振り返り: 「どのレイヤーが最も価値があるか？」
- [ ] 最終判定: 全4層出荷 or 非効果的レイヤー無効化

### Timeline Summary

| Week | Phase | コスト |
|------|-------|-------|
| 1 | Layer 0 Deploy | 1時間 (**DONE**) |
| 2-3 | Layer 0 Measure | 5時間 |
| 4 | Layer 1 Deploy | 3-4時間 |
| 5 | Layer 1 Measure | 5時間 |
| 6 | Layer 2A Deploy | 2-4時間 |
| 7-9 | Layer 2B Implement | 25-30時間 |
| 10-11 | Hybrid Validate | 5時間 |

**全層実装の場合**: 31-39時間（progressive validationにより早期停止可能）
**期待コスト**: 約10時間（確率加重: L0で30%停止、L1で50%停止、L2Aで15%停止）

---

## Known Risks

| リスク | 確率 | 影響 | 緩和策 |
|-------|------|------|-------|
| Layer 0 compliance <65% | Medium | 期待値低下 | Variant 3（6行版）にダウングレード or 親バリデーション追加 |
| Layer 2A sycophancy >25% | Medium | 高リスクタスクで不十分 | Layer 2B（専用ワーカー）にフォールバック |
| Layer 2B invocation rate <20% | High | 投資回収不足 | 親セッションの提案ロジック追加 or パワーユーザー限定と割り切り |
| Layer 2A false positive >30% | Medium | ユーザー疲弊 | Red Pen Protocol精緻化 or Layer 2A opt-in化 |
| 確率分布の予測誤差 | High | ロードマップ逸脱 | 各Phase判定ゲートで実測値に基づき修正 |

---

## Design References

| Round | cmd | 内容 |
|-------|-----|------|
| R1 | cmd_079 | 初期設計（19タスク、過剰設計） |
| R2 | cmd_080 | 批評レビュー（過剰設計の指摘） |
| R3 (mutation) | cmd_081 | 前提逆転（ハイブリッドスキルアーキテクチャ提案） |
| R4 | cmd_082 | Design v2統合 |
| R5 (mutation) | cmd_083 | 敵対的レビュー（null仮説チャレンジ） |
| R6 | cmd_084 | null仮説対決（Design C: 段階的アプローチ採用） |
| R7 | cmd_085 | 実装仕様（Layer 0+1 diff、/mutateスキル仕様） |
| R8 (mutation) | cmd_086 | 代替探索（Enhanced Reviewer発見） |
| R9 | cmd_087 | 最終統合設計ドキュメント |
| R10 | cmd_088 | 最終バリデーション（CONDITIONAL PASS） |
