# claude-crew

Claude Code + Task tool サブエージェントによるマルチエージェントシステム。
1セッション完結型の2層フラット構成で、全やり取りをファイル経由で行う。

## アーキテクチャ

```
人間 ←→ 親セッション（パス受け渡し係）
              │
              ├── Task(分解役)     … Phase 1
              ├── Task(検証役)     … Phase 1.5 (optional)
              ├── Task(実働A-C)   … Phase 2（並列）
              ├── Task(集約役)     … Phase 3
              └── Task(回顧役)     … Phase 4
```

- **2層フラット構成**: 親が全サブエージェントを直接生成・管理。ネスト不可
- **ファイル経由**: 入出力は全てファイル。親はファイルパスを渡すだけ
- **処理を開始する前に `docs/parent_guide.md` を Read し、詳細な処理フローに従え**

## ワークフロー強制

このプロジェクト上での作業時、crew ワークフロー（Phase 1 → Phase 2 → Phase 3）の使用を**必須**とする。

### 親セッションの役割制限

**禁止**: 以下の作業を親セッションが直接行うこと
- ファイルの直接編集・作成（Edit, Write の直接使用）
- コード実装・リファクタリング
- 調査・分析作業
- ドキュメント執筆
- テストの実行と結果の分析

**許可**: 以下の作業のみ親セッションが行える
- パス受け渡し（サブエージェントへのファイルパス指示）
- 進捗報告（ユーザーへのステータス通知）
- ユーザーへの説明（ワークフロー説明、結果サマリ報告）
- 承認フローの実施（Memory MCP書き込み、改善提案適用、コミット作成）
- execution_log.yaml の更新

### Phase 1（タスク分解）の必須化

Phase 1（decomposer起動）は**原則必須**である。タスクの複雑度・サブタスク数に関係なく、decomposerを起動してタスク分解を行え。

**例外条件**: 以下の場合に限り Phase 1 を省略してよい
- 1ファイル1箇所の typo修正（例: 誤字脱字の修正のみ）
- 既存ファイルへの1行追加・削除（新規実装・ロジック変更を含まない）
- `config.yaml` の単一値変更（version bump、閾値変更等）
- `execution_log.yaml` の更新
- 承認フローの実施（Memory MCP書き込み、改善提案のコミット等）
- ユーザーへの報告・説明のみ

上記例外に該当しない全てのケースでは、必ず decomposer を起動し、タスクを独立サブタスクに分解してから Phase 2 へ進むこと。

### よくある間違い

**間違い**: 親セッションが「単純なタスクだから」と判断して直接 Edit/Write を使う

**問題点**:
- 成果物に YAML frontmatter が付かず、Phase 4 のメタデータバリデーションで失敗する
- execution_log.yaml にサブエージェント実行記録が残らず、追跡不能になる
- 並列実行の利点が失われ、複数ファイルの変更が直列化される

**正解**: 例外条件に該当しない限り、必ず decomposer を起動してタスク分解を行う

## 設定ファイル

`config.yaml` は必須。存在しない場合はエラーで停止せよ。フィールド定義は `config.yaml` 本体を参照。

## バージョン管理

- `config.yaml` の `version` が現在のバージョン
- 成果物にはYAMLフロントマターで `generated_by`, `date`, `cmd_id` を含める
- `CHANGELOG.md` に変更履歴を記録
- 改善提案の承認時、Conventional Commits 形式で自動コミットする（詳細は `docs/parent_guide.md` 参照）

## テンプレート参照規約

| 役割 | テンプレート | 用途 |
|------|-------------|------|
| 分解役 | `templates/decomposer.md` | タスクを独立サブタスクに分解 |
| 実働（共通ルール） | `templates/worker_common.md` | 全workerの共通ルール（YAML frontmatter, Memory MCP候補, 必須ルール） |
| 実働（デフォルト） | `templates/worker_default.md` | DEPRECATED — 使用禁止。専門ペルソナを使用せよ |
| 実働（調査） | `templates/worker_researcher.md` | リサーチ・情報収集 |
| 実働（ライティング） | `templates/worker_writer.md` | ドキュメント作成・コンテンツ執筆 |
| 実働（コーディング） | `templates/worker_coder.md` | コード実装・修正 |
| 実働（レビュー） | `templates/worker_reviewer.md` | コードレビュー・品質チェック |
| 実働（カスタム） | `personas/*.md` | ユーザー定義のカスタムペルソナ（オプション） |
| 集約役 | `templates/aggregator.md` | 複数結果の統合・最終報告作成 |
| 回顧役 | `templates/retrospector.md` | cmd完了後の分析・改善提案生成 |
| 分析補助 | `templates/multi_analysis.md` | N観点並列分析フレームワーク（decomposerが参照） |

**テンプレートの使い方**:
1. prompt にテンプレートパス（TEMPLATE_PATH）を明記する
2. サブエージェントが最初のアクションとしてテンプレートを Read する
3. 親はテンプレートの内容を読まない

## 安全性

- サブエージェントは親セッションのパーミッション設定を継承する
- 3段階制御: deny（自動拒否）> ask（毎回確認）> allow（自動許可）
- 詳細は `.claude/settings.json` 参照。deny リストの操作はバイパス不可
- **PermissionRequest hook**: `.claude/hooks/permission-fallback.sh` は python3/bash/sh による scripts/ 配下・.claude/hooks/ 配下スクリプト実行を動的に承認する。8段階検証パイプライン（正規化 → サフィックス除去 → 前解析 → 解析 → オプション正規化 → パス正規化 → 判定 → 汎用コマンド承認）で入力を厳密に検証し、path traversal/変数展開/危険フラグ注入を防止する

## Memory MCP活用

サブエージェントはタスク開始時に `mcp__memory__search_nodes` で関連知識を検索する。
メモリへの書き込みは Phase 4 完了後の一括承認フローで人間が承認した候補のみ実行する。

**品質基準**: 即却下条件（cmd参照、内部アーキテクチャ記述、既知一般知識）を除外し、Cross-cmd適用可能性・行動変容可能性・観測の具体性を全て満たす候補のみ記録する。
命名規約: `{domain}:{category}:{identifier}`

## Learned Preferences (LP)

LP System は、ユーザーの作業パターンから好みを学習し、繰り返し指示するコストを削減する。プロファイリングではなく、翻訳コスト削減が目的。

### 仕組み

1. **Signal Detection**: retrospector がユーザーの修正・追加要求パターンを検出（コース修正、後付け要求、拒否、繰り返し指定）
2. **Distillation**: N>=3 蓄積で LP 候補生成（what, evidence, scope, action の4要素形式）
3. **Approval**: 人間が承認した候補のみ Memory MCP に記録（Principle 5）
4. **Application**: worker が黙って適用、ユーザーは気づかない（Principle 1）

### 5つの原則

| 原則 | 内容 |
|------|------|
| **1. 黙って使え** | LP適用をユーザーに通知しない（作業中）。自然に反映 |
| **2. デフォルトであって強制ではない** | タスク指示が明示的に異なる場合、指示が優先。LPを上書き可 |
| **3. 絶対品質は不変** | 正確性・安全性・完全性・セキュリティ・テストカバレッジは LP で変えない。相対品質のみ調整可（スタイル、設計選択、報告形式、確認頻度等） |
| **4. 変化を許容する** | LP は更新・廃止可能。矛盾シグナル検出で更新候補生成 |
| **5. 承認なしに記録しない** | 全 LP 候補は人間承認必須。retrospector は提案のみ |

### 品質ガードレール

**絶対品質（IMMUTABLE）**: 正確性、完全性、セキュリティ、安全性、テストカバレッジ
→ LP で絶対に妥協不可。「テストをスキップ」「不完全な実装を受け入れる」「データ損失OK」などのLPは禁止

**相対品質（LP-ADJUSTABLE）**: コードスタイル、設計パターン、ドキュメント詳細度、確認頻度、報告形式
→ LP で調整可。複数の正解がある選択肢

判定ルール: 同じ機能結果を複数のアプローチで実現可能か？ YES→相対品質、NO→絶対品質

### LP Entity フォーマット

**命名規約**: `lp:{cluster}:{topic}`

**6つのクラスタ**:
- `vocabulary`: ユーザーの用語定義（"簡単化" = 依存削減、行数削減ではない）
- `defaults`: 繰り返し指定される値（言語選択、テストフレームワーク）
- `avoid`: 一貫して拒否されるもの（linter設定変更禁止、早期抽象化回避）
- `judgment`: トレードオフ判断パターン（可読性 vs パフォーマンス、DRY vs 明示）
- `communication`: 対話スタイル（確認頻度、報告詳細度）
- `task_scope`: タスクスコープ拡張パターン（バグ修正→テスト更新も含む）

**Observation形式**:
```
[what] 傾向記述 [evidence] 根拠（N回観測） [scope] 適用条件 [action] AI行動指針
```

### プライバシー保護

1. **Cluster名変更**: `implicit` → `task_scope` に変名（認知推論ではなく具体的タスクスコープ拡張のみ記録）
2. **Aggregate Profile Review**: LP数マイルストーン（10, 20, 30）で全LP一覧を提示。個別承認≠集約プロファイル同意のギャップを解消
3. **One-Command Reset**: `config.yaml: lp_system.reset_all: true` で全LP削除 + システム無効化
4. **Forbidden Categories**: 以下は絶対記録禁止
   - 感情状態・ストレス反応
   - パーソナリティ特性（Big Five等）
   - 作業スケジュール・時間習慣
   - 生産性メトリクス・出力率
   - 健康・ウェルネス指標
   - 政治・社会・哲学的見解
   - 人間関係・チームダイナミクス
   - 金銭・報酬情報

### 統合ポイント

- **worker_common.md**: LP検索・適用・安全性チェック（絶対品質保護）
- **retrospector.md**: シグナル検出・蓄積・LP候補生成・品質フィルタ
- **親セッション**: Phase 4後の一括承認フロー（Memory MCP + LP統合提示）

LP は任意機能。`config.yaml: lp_system.enabled: false` でいつでも無効化可能。

## コンテキスト管理

- 1依頼1サイクルがコンパクションなしで完走できることが目標
- 親は「パス受け渡し係」に徹し、タスク本文やresult本文は読まない
- 長い結果を返すサブエージェントは `run_in_background: true` で起動する
