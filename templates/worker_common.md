# Worker Common Rules

このファイルは全workerテンプレートの共通ルールを定義する。
各workerテンプレートの指示に従う前に、このファイルの内容を理解せよ。

## Output Format (共通)

> ⚠️ Writing this file to RESULT_PATH is mandatory. You must write it regardless of task success or failure.

全てのworkerは以下のYAMLフロントマター形式で結果を記述すること:

```markdown
---
status: success          # success / partial / failure (required)
quality: GREEN           # GREEN / YELLOW / RED (self-assessment, required)
completeness: 100        # 0-100 % (required)
errors: []               # error list (required, [] if none)
warnings: []             # warning list (optional, [] if none)
output_files:            # list of generated files (optional)
  - result_N.md
task_id: N               # task number (required)
---
```

YAMLブロックの後に続く本文は各workerのペルソナに応じて異なる。

## Memory MCP追加候補 (共通)

タスク実行中に**将来の別タスクで再利用可能な**知見を発見した場合のみ、resultファイル末尾に以下の形式で記載せよ（該当なしの場合は省略可。出さないことは正常な結果である）:

**候補にしてよいもの**:
- プロジェクト固有の慣習・制約で、外部ドキュメントにない情報（例: "このユーザーはXXXを好む"）
- 複数タスクで再現された具体的なパターン（例: "YYYの場合はZZZが有効"）
- 失敗から導出された具体的な判断基準（例: "条件AならBを避け、Cを選べ"）

**候補にしてはいけないもの**:
- 特定cmdへの言及（cmd_NNN）
- claude-crewの内部処理の記述（decomposer, aggregator, Phase等）
- Claudeの事前学習で既知の一般知識
- 行動に落とせない抽象論
- 今回のタスクの実行結果メトリクス

フォーマット:

    ## Memory MCP追加候補
    - name: "{domain}:{category}:{identifier}"
      type: best_practice / failure_pattern / tech_decision / lesson_learned
      observation: "[What] パターン記述 [Evidence] 根拠 [Scope] 適用条件"

## Learned Preferences (LP) — Optional

**タスク開始時**: `mcp__memory__search_nodes(query="lp:")` を実行し、関連するLP(学習済み好み)があれば取得せよ。LPは以下の形式で記録されている:

```
[what] 傾向記述 [evidence] 根拠 [scope] 適用条件 [action] AI行動指針
```

**完全な例**:
```
[what] Linter/formatter設定ファイルは変更しない [evidence] AI提案の設定変更を3回revert [scope] Universal [action] Linter/formatter設定変更は絶対に行わない。必要な場合は明示的な許可を求める
```

**適用原則**:
1. **黙って使え（作業中）**: LP適用をユーザーに通知しない。自然に反映せよ。**ただし例外**: ユーザーが「なぜXをしたのか？」と直接質問した場合、LPの影響を簡潔に説明してよい（"以前の好みに基づいて〜"程度）
2. **デフォルトであって強制ではない**: タスク指示が明示的に異なる要求をした場合、タスク指示が優先。LPを上書き
3. **絶対品質は不変**: 正確性・安全性・完全性・セキュリティ・テストカバレッジはLPで変えてはならない。LPで調整可能なのは相対品質のみ(スタイル、設計選択、報告形式、確認頻度等)

**使い方**:
- `[scope]` を確認し、**現在のプロジェクト・タスクタイプ・技術スタックに関連するか判定**
- 関連する場合、`[action]` の指針を行動デフォルトとして適用
- LPが見つからない、または関連性が低い場合は通常通り実行

**例**: `lp:avoid:linter_changes` のLPが「設定ファイルは変更しない」と指示している場合、リファクタリングタスク内でlinter設定の最適化が考えられても実行しない。ただしタスクが明示的に「ESLint設定を更新して」と指定していればそちらが優先。

**Principle 1の補足**: 「黙って使え」はworkerの作業実行中の原則である。Retrospectorによる承認フロー（Principle 5）では当然LPの内容を明示する。2つの原則は矛盾しない。

## Common Rules

- **YAMLフロントマターのメタデータブロックは絶対必須。** `---` で囲んだYAMLブロックをファイル先頭に配置し、status, quality, completeness, errors, task_id を必ず含めよ。
- **RESULT_PATH への書き込みは【絶対必須】。これが最も重要な責務である。**
- エラー・ブロック・不明な状況が発生しても、必ず RESULT_PATH に結果ファイルを生成せよ。
- 失敗した場合は、失敗の経緯・理由を result ファイルに記載せよ（空ファイルやファイル未生成は禁止）。
- Mask secrets: API keys → `***API_KEY***`, passwords → `***PASSWORD***`
- **完了マーカー**: ファイル書き込みの最終行に `<!-- COMPLETE -->` を必ず追記せよ。このマーカーが親による書き込み完全性チェックに使われる。
