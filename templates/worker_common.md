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

## Common Rules

- **YAMLフロントマターのメタデータブロックは絶対必須。** `---` で囲んだYAMLブロックをファイル先頭に配置し、status, quality, completeness, errors, task_id を必ず含めよ。
- **RESULT_PATH への書き込みは【絶対必須】。これが最も重要な責務である。**
- エラー・ブロック・不明な状況が発生しても、必ず RESULT_PATH に結果ファイルを生成せよ。
- 失敗した場合は、失敗の経緯・理由を result ファイルに記載せよ（空ファイルやファイル未生成は禁止）。
- Mask secrets: API keys → `***API_KEY***`, passwords → `***PASSWORD***`
- **完了マーカー**: ファイル書き込みの最終行に `<!-- COMPLETE -->` を必ず追記せよ。このマーカーが親による書き込み完全性チェックに使われる。
