---
generated_by: "claude-crew v1.0"
date: "2026-02-15"
cmd_id: "cmd_105"
status: success
---

# Secretary Pattern 実装ロードマップ

## 概要

親セッションのコンテキスト消費（現状27-35%）を段階的に削減し、マルチcmdセッションの寿命を3-5 cmdから5-8 cmdへ延長する。

**推奨判断: Conditional Go** — Phase 3 からの段階的導入。

## 現状の課題

| 指標 | 現状 |
|------|------|
| 親コンテキスト消費 | 総cmdバジェットの27-35% |
| マルチcmdセッション寿命 | 3-5 cmd（100Kウィンドウ） |
| 最大消費フェーズ | Phase 2（35-45%）、Phase 4（20-35%） |
| パス受け渡し係原則の遵守率 | 約85%（plan.md全文読み、Phase 4承認フロー等で違反） |

---

## Phase A: Quick Wins（Secretary不要）

**目的**: 既存アーキテクチャ内でコンテキストを最適化する。

### A-1: plan.md の遅延読み込み

**現状**: plan.md を全文読みして依存関係グラフを構築。
**改善**: Depends On列・Persona列・Model列のみ抽出する構造化メタデータ（wave_plan.json）を decomposer が同時出力。親はJSONだけ読む。

- 節約: 300-500トークン/cmd
- 変更箇所: `templates/decomposer.md`（wave_plan.json出力追加）、`docs/parent_guide.md`（Phase 2手順更新）
- リスク: LOW（スキーマ変更時のバージョン管理が必要）

### A-2: stats.sh 出力のキャッシュ

**現状**: ETA計算のために毎cmd `stats.sh` を実行し、出力をコンテキストに取り込む。
**改善**: 出力を `work/stats_cache.json` にキャッシュ。10cmd以上のログが蓄積するまでフォールバック推定値を使用。

- 節約: 500-1,000トークン/cmd
- 変更箇所: `scripts/stats.sh`（キャッシュ出力追加）、`docs/parent_guide.md`（ETA計算手順更新）
- リスク: LOW

### A-3: result メタデータの execution_log 統合

**現状**: 各 result_N.md の先頭20行を繰り返し読んでステータス確認。
**改善**: validate_result.sh の検証結果を execution_log.yaml に一度記録し、以降はlogから参照。

- 節約: 500-800トークン/cmd
- 変更箇所: `docs/parent_guide.md`（Phase 2手順4更新）
- リスク: LOW

### Phase A まとめ

| 指標 | 値 |
|------|-----|
| 合計節約 | 1,300-2,300トークン/cmd（親バジェットの7-10%） |
| レイテンシ増 | 0秒 |
| リスク | LOW |
| 検証期間 | 2-3 cmd |
| 累計削減率 | 7-10% |

---

## Phase B: Phase 3 Secretary 導入

**目的**: report_summary.md の生成を秘書エージェントに委譲する。

### なぜ Phase 3 から始めるか

1. **100%のcmdで実行される**（条件分岐なし → 効果が安定）
2. **単方向通信**（親→秘書→ファイル → 伝言ゲームリスク最小）
3. **フォールバックが容易**（秘書が失敗したら親が直接読む＝現状と同じ動作）
4. **精度要件が低い**（要約の品質問題はユーザー体験を直接損なわない）

### 秘書エージェントの仕様

| 項目 | 値 |
|------|-----|
| モデル | haiku |
| max_turns | 10 |
| ライフサイクル | per-phase stateless（Phase 3開始時に起動、完了後に破棄） |
| 入力 | secretary_request.md（操作指示 + ファイルパス群） |
| 出力 | secretary_response.md（≤50行のYAMLフロントマター付き要約） |
| フォールバック | タイムアウト/失敗時 → 親が直接 result メタデータを読む |

### 通信プロトコル

```
親セッション                         秘書エージェント
    │                                    │
    ├── secretary_request.md 作成 ──────→│
    │   (operation: phase3_report)        │
    │   (RESULTS_DIR, PLAN_PATH 等)      │
    │                                    ├── result群を読む
    │                                    ├── report.md を生成
    │                                    ├── report_summary.md を生成
    │                                    ├── secretary_response.md を書く
    │←── Task tool 完了通知 ─────────────│
    │                                    │（破棄）
    ├── report_summary.md を読む
    ├── ユーザーに報告
```

### コンフィグ

```yaml
# config.yaml に追加
secretary:
  enabled: true
  min_tasks_for_delegation: 4    # 4タスク未満のcmdではスキップ
  delegate_phases:
    - phase3_report              # Phase B: パイロット
  model: haiku
  max_turns: 10
  fallback_on_failure: true      # 秘書失敗時に親が直接実行
```

### 成功基準

- [ ] 10 cmd連続で秘書が report_summary.md を正常生成
- [ ] レイテンシ増が +30秒/cmd 以内
- [ ] report_summary.md の品質がユーザーから問題報告なし
- [ ] フォールバック発動率 < 10%

### Phase B まとめ

| 指標 | 値 |
|------|-----|
| 追加節約 | 500-800トークン/cmd |
| レイテンシ増 | +15-20秒/cmd |
| リスク | LOW-MEDIUM |
| 検証期間 | 5-10 cmd |
| 累計削減率 | 15-20% |

---

## Phase C: Phase 2 Secretary（波構築の委譲）

**目的**: plan.md の依存関係解析 → Wave割り当て → workerプロンプト構築を秘書に委譲する。

### なぜ Phase 2 が重要か

- Phase 2 は親コンテキストの **35-45%** を占める最大消費者
- Wave 1〜N のプロンプト構築で60-80行/Waveが親コンテキストに蓄積
- ただし依存関係の解析ミスがカスケード障害を引き起こすため、慎重な導入が必要

### 前提条件（着手前に必須）

1. **回帰テストスイート**: 既存の plan.md 20件以上で波割り当てを検証し、精度 **≥98%** を確認
2. **バリデーション層**: 秘書の波割り当て結果を親が依存関係制約で二重チェック
3. **Phase B の安定稼働実績**: 10+ cmd で秘書パターンが安定していること

### 秘書の動作

1. 親が `secretary_request.md` に operation: `phase2_wave_construct` を指示
2. 秘書が plan.md を読み、依存関係を解析し、Wave割り当てを計算
3. 秘書が `secretary_response.md` に構造化データを出力:
   ```yaml
   waves:
     - wave: 1
       tasks: [1, 3]
     - wave: 2
       tasks: [2, 5]
       depends_on_wave: [1]
   ```
4. 親がバリデーション: 各Wave Nのタスクの依存元がWave 1〜N-1に含まれるか確認
5. バリデーション失敗 → フォールバック（親が plan.md を直接読む）

### 最大のリスク: カスケード障害

```
秘書が依存関係を誤読
  → Task 3 を Wave 2 に割り当て（正しくは Wave 3）
    → Wave 2 で Task 3 が実行されるが、依存する Task 2 の result が未生成
      → Task 3 が failure
        → Task 3 に依存する Task 5, 6 も skipped
          → cmd全体が partial failure
```

**緩和策**: 親側バリデーション層 + フォールバック + 回帰テスト

### コンフィグ更新

```yaml
secretary:
  delegate_phases:
    - phase3_report
    - phase2_wave_construct    # Phase C で追加
```

### 成功基準

- [ ] 回帰テスト20件で波割り当て精度 100%
- [ ] 20 cmd連続で秘書の波構築が正常完了
- [ ] バリデーション層によるフォールバック発動率 < 5%
- [ ] カスケード障害の発生件数 0

### Phase C まとめ

| 指標 | 値 |
|------|-----|
| 追加節約 | 800-1,500トークン/cmd |
| レイテンシ増 | +20-30秒/cmd |
| リスク | MEDIUM |
| 検証期間 | 10-20 cmd |
| 累計削減率 | 20-30% |

---

## Phase D: Phase 4 Secretary（承認フロー整形）— オプション

**目的**: retrospective.md の改善提案・スキル提案・知識候補をユーザー提示用フォーマットに整形する作業を委譲する。

### 効果とリスクのトレードオフ

Phase Dは **最大効果かつ最大リスク** のフェーズ。

| 指標 | 値 |
|------|-----|
| 効果（fullモード発動時） | 4,000-12,000トークン/cmd |
| 発動率 | 30-50%（fullモードのcmd） |
| 情報ロスリスク | 1,500行→50行で95%情報ロス |

### 緩和策

1. **Verbatim Passthrough**: Evidence / Scope / Dependencies フィールドは要約せず原文転送
2. **出力制限の拡大**: Phase 4のみ max_output_lines を 100 に拡大
3. **バッチ分割**: 提案3件以上なら秘書を2回に分けて呼ぶ
4. **ユーザー確認の強化**: 秘書要約に「詳細は retrospective.md を参照」のリンクを必ず付与

### 着手判断

Phase C の安定稼働（20+ cmd）が確認され、かつ Phase 4 fullモードの発動頻度が30%以上ある場合に着手。発動頻度が低い場合はROIが合わないため見送り。

### Phase D まとめ

| 指標 | 値 |
|------|-----|
| 追加節約 | 4,000-12,000トークン/cmd（発動時） |
| レイテンシ増 | +20-40秒/cmd |
| リスク | HIGH |
| 検証期間 | 20-30 cmd |
| 累計削減率 | 27-34% |

---

## 全体タイムライン

```
Phase A ──[2-3 cmd]──→  7-10% 削減  ← Secretary不要、即着手可
     │
Phase B ──[5-10 cmd]──→ 15-20% 累計 ← 本命。ここが最大のROI
     │
     ├── Go/No-Go 判断ポイント
     │
Phase C ──[10-20 cmd]─→ 20-30% 累計 ← Phase 2が最大消費者なので効果大
     │
Phase D ──[20-30 cmd]─→ 27-34% 累計 ← オプション。リスク高
```

## セッション寿命の改善見込み

| Phase | 親コンテキスト消費 | セッション寿命 |
|-------|-------------------|---------------|
| 現状 | 27-35% | 3-5 cmd |
| Phase A完了 | 22-28% | 3-5 cmd（微改善） |
| Phase B完了 | 18-23% | 4-6 cmd |
| Phase C完了 | 12-18% | 5-7 cmd |
| Phase D完了 | 8-12% | 5-8 cmd |

## ロールバック戦略

各Phaseは独立した feature flag で制御。問題発生時は該当Phaseのみ無効化。

```yaml
# ロールバック例: Phase C で問題発生
secretary:
  delegate_phases:
    - phase3_report              # Phase B: 維持
    # - phase2_wave_construct    # Phase C: 無効化
```

秘書が3回連続で失敗した場合、セッション内で自動的に無効化する（`fallback_on_failure: true`）。

## 実装の優先順位

| 優先度 | 作業 | 前提 |
|--------|------|------|
| 1 | config.yaml に `secretary` セクション追加 | なし |
| 2 | `templates/secretary.md` テンプレート作成 | なし |
| 3 | Phase A-1〜A-3 の quick wins 実装 | なし |
| 4 | Phase B: Phase 3 秘書委譲を parent_guide.md に統合 | 1, 2 |
| 5 | Phase B の検証（5-10 cmd） | 4 |
| 6 | Phase C: 回帰テストスイート + バリデーション層 | 5 の成功 |
| 7 | Phase C: Phase 2 秘書委譲を parent_guide.md に統合 | 6 |
| 8 | Phase D: 着手判断 | 7 の成功 |

## 関連成果物

- `work/cmd_105/results/result_1.md` — 現状分析（537行）
- `work/cmd_105/results/result_2.md` — アーキテクチャ設計（1,041行）
- `work/cmd_105/results/result_3.md` — 効果見積もり（841行）
- `work/cmd_105/results/result_4.md` — リスク分析（887行）
- `work/cmd_105/results/result_5.md` — 代替手法比較（663行）
