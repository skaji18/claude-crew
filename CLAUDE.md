# claude-crew

Claude Code + Task tool サブエージェントによるマルチエージェントシステム。
1セッション完結型の2層フラット構成で、全やり取りをファイル経由で行う。

## アーキテクチャ

```
人間 ←→ 親セッション（パス受け渡し係）
              │
              ├── Task(分解役)     … フェーズ1
              ├── Task(実働A-C)   … フェーズ2（並列）
              ├── Task(集約役)     … フェーズ3
              └── Task(回顧役)     … フェーズ4
```

- **2層フラット構成**: 親が全サブエージェントを直接生成・管理。ネスト不可
- **ファイル経由**: 入出力は全てファイル。親はファイルパスを渡すだけ
- **処理を開始する前に `docs/parent_guide.md` を Read し、詳細な処理フローに従え**

## 設定ファイル

`config.yaml` は必須。存在しない場合はエラーで停止せよ。
```yaml
version: "0.8.0"
default_model: sonnet
max_parallel: 10
max_retries: 2
background_threshold: 5
worker_max_turns: 30
retrospect:
  enabled: true
  filter_threshold: 3.5
  model: sonnet
  full_mode:
    max_improvements: 2
    max_skills: 1
  light_mode:
    max_skills: 2
  memory:
    max_candidates_per_cmd: 5
    skill_min_score: 12
```

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
- **PermissionRequest hook**: `.claude/hooks/permission-fallback.sh` は python3/bash/sh による scripts/ 配下スクリプト実行を動的に承認する。6段階検証パイプライン（正規化 → 前解析 → 解析 → オプション正規化 → パス正規化 → 判定）で入力を厳密に検証し、path traversal/変数展開/危険フラグ注入を防止する

## Memory MCP活用

サブエージェントはタスク開始時に `mcp__memory__search_nodes` で関連知識を検索する。
メモリへの書き込みは Phase 4 完了後の一括承認フローで人間が承認した候補のみ実行する。

**品質基準**: 即却下条件（cmd参照、内部アーキテクチャ記述、既知一般知識）を除外し、Cross-cmd適用可能性・行動変容可能性・観測の具体性を全て満たす候補のみ記録する。
命名規約: `{domain}:{category}:{identifier}`

## コンテキスト管理

- 1依頼1サイクルがコンパクションなしで完走できることが目標
- 親は「パス受け渡し係」に徹し、タスク本文やresult本文は読まない
- 長い結果を返すサブエージェントは `run_in_background: true` で起動する
