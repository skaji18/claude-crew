# claude-crew

Claude Code + Task tool サブエージェントによるマルチエージェントシステム。
1セッション完結型の2層フラット構成で、全やり取りをファイル経由で行う。

## アーキテクチャ

```
人間 ←→ 親セッション（パス受け渡し係）
              │
              ├── Task(分解役)     … フェーズ1
              │
              ├── Task(実働A)  ─┐
              ├── Task(実働B)   ├─ フェーズ2（並列）
              ├── Task(実働C)  ─┘
              │
              ├── Task(集約役)     … フェーズ3
              │
              └── Task(回顧役)     … フェーズ4
```

- **2層フラット構成**: 親セッションが全サブエージェントを直接生成・管理する
- **ネスト不可**: サブエージェントから更にサブエージェントは起動できない
- **ファイル経由**: サブエージェントへの入出力は全てファイルで行う。親はファイルパスを渡すだけ
- **親はパス受け渡し係に徹する**（詳細は「パス受け渡し係」原則の許容範囲を参照）

## 設定ファイル

`config.yaml` に設定値を外部化している。タスク開始時に `config.yaml` を読み、設定値を取得せよ。
`config.yaml` は必須である。存在しない場合はエラーで停止せよ。
エラーメッセージ例: `"ERROR: config.yaml not found. Create config.yaml with the following format:"`
必須フォーマット:
```yaml
version: "0.7.2"
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
```

## バージョン管理

- `config.yaml` の `version` フィールドが現在のバージョンを示す
- 成果物（plan.md, report.md, report_summary.md）にはYAMLフロントマターでバージョンメタデータを含める: `generated_by`, `date`, `cmd_id` フィールド（詳細は各テンプレート参照）
- `CHANGELOG.md` に変更履歴を記録する

## 処理フロー

人間からタスクを受けたら、以下の4フェーズで処理する。

### フェーズ1: 分解（Decompose）

1. `work/cmd_xxx/` ディレクトリを作成する（xxxは連番）:
   ```bash
   ./scripts/new_cmd.sh
   ```
   - パーミッション確認を不要にするため、スクリプトはフルパスで指定してはならない
   - スクリプト内部でmkdirのアトミック性 + 最大5回リトライにより衝突を回避
   - 成功時は `cmd_NNN` を標準出力に返す
2. 人間の依頼内容を `work/cmd_xxx/request.md` に書く
3. 分解役サブエージェントを起動する:
   - テンプレートパス（TEMPLATE_PATH）: `templates/decomposer.md`
   - 入力パス（REQUEST_PATH）: `work/cmd_xxx/request.md`
   - 出力パス（PLAN_PATH）: `work/cmd_xxx/plan.md`
   - タスク出力先（TASKS_DIR）: `work/cmd_xxx/tasks/`
   - prompt に TEMPLATE_PATH + 上記3パスを明記する（テンプレートの内容は含めない）
4. 結果: `work/cmd_xxx/plan.md` にタスク分解結果が書かれる
   - 各サブタスクが `work/cmd_xxx/tasks/task_N.md` として生成される

### フェーズ2: 実行（Execute）

1. `work/cmd_xxx/plan.md` のタスク一覧を確認する（親はファイルパスだけ確認）
   - 確認する情報: タスク数、各タスクのファイルパス、Depends On列（依存関係）、Persona、Model
   - **タスクの詳細内容（Description等）は読まない**（パス受け渡し係原則）
2. **依存関係グラフに基づきタスクをグループ化する**:
   a. `Depends On` が `-`（依存なし）のタスクを **Wave 1** としてグループ化
   b. Wave 1 のタスクに依存するタスクを **Wave 2** としてグループ化
   c. 以降、依存元が全て処理済みのタスクを次の Wave にグループ化（全タスク割当まで繰り返し）
3. **Wave 1 を並列実行する**:
   - 各タスクに対して実働サブエージェントを起動する:
     - テンプレートパス（TEMPLATE_PATH）: `templates/worker_xxx.md` からタスクに適したものを選択
     - 入力パス: `work/cmd_xxx/tasks/task_N.md`
     - 出力パス: `work/cmd_xxx/results/result_N.md`
     - prompt に TEMPLATE_PATH + 入出力パスを含める（テンプレートの内容は含めない）
   - **独立したタスクは1メッセージ内で複数の Task tool 呼び出しを行い並列実行する**
4. **Wave 完了確認 → 次の Wave へ進む**:
   a. 現在の Wave の全タスクが完了したら、`results/` 内の result_N.md 存在をチェック
   b. 各resultファイルの**完了マーカー**と**メタデータヘッダー**を検証する:
      1. 完了マーカーチェック: `tail -1` (Bash) でファイル最終行を取得し、`<!-- COMPLETE -->` の存在を確認する
         - `<!-- COMPLETE -->` なし → 不完全書き込みとみなし、リトライ対象
         - `<!-- COMPLETE -->` あり → 次のステップ（メタデータ確認）に進む
      2. メタデータヘッダーを読み（Read tool, limit=20）、statusフィールドを確認:
         - status: "success" → 完了とみなす
         - status: "partial" または "failure" → リトライ対象
         - メタデータヘッダーがない場合 → 従来通り存在チェックのみで判定（フォールバック）
   c. **メタデータバリデーション**: 手順bで読み取ったYAMLフロントマターの必須3項目を検証する:
      - **status**: 欠落時 → `status: failure` として扱う（品質不明のため安全側に倒す）
      - **quality**: 欠落時 → `quality: YELLOW` を付与（品質不明のため）
      - **completeness**: 欠落時 → `completeness: 0` として扱う
      - 検証結果を execution_log.yaml の該当タスクの `metadata_issues` に記録する（例: `quality missing, defaulted to YELLOW`）
      - 3項目全て存在する場合は検証パス。`metadata_issues` は空リスト `[]` のまま
   d. **構造的品質検証**: ファイル本文を読まずに客観指標で品質をチェックする（親はメタデータのみ読む原則を維持）:
      - **行数チェック（全ペルソナ共通）**: `wc -l` (Bash) で行数を取得。20行未満 → `quality: RED` に上書きし、リトライ対象とする
      - **Sourcesセクション（researcher のみ）**: `grep -c '## Sources' RESULT_PATH` (Bash) で確認。0件 → 警告のみ（execution_log.yaml の `metadata_issues` に `"Sources section missing"` を追記）。リトライはしない
      - **コードブロック（coder のみ）**: `` grep -c '```' RESULT_PATH `` (Bash) で確認。0件 → 警告のみ（execution_log.yaml の `metadata_issues` に `"code block missing"` を追記）。リトライはしない
   e. 欠落またはstatus=failure/partialの場合は該当タスクをリトライ（最大 `config.yaml: max_retries` 回）
   f. 全resultがstatus=success（またはリトライ上限に達した）ら、次のWaveを並列実行
   g. **依存元が未完了のタスクは絶対に実行しない**
   h. 全 Wave が完了するまで繰り返す
5. 結果: `work/cmd_xxx/results/result_N.md` に各タスクの成果が書かれる
6. **タイムアウト処理**: worker が `config.yaml: worker_max_turns` に到達した場合:
   a. execution_log.yaml の該当タスクに `status: timeout` として記録する
   b. 該当タスクをリトライ対象とする（最大 `config.yaml: max_retries` 回）
   c. リトライ上限到達時: result を `status: partial` として記録し、次の Wave へ進む
7. **最終検証**: 全Waveの完了後、以下を実行する:
   a. `work/cmd_xxx/results/` ディレクトリ内のファイル一覧を取得（Glob tool使用）
   b. plan.md のタスク一覧と照合し、以下を確認:
      - 欠落している result_N.md がないか
      - 各resultの完了マーカー（`<!-- COMPLETE -->`）とメタデータヘッダーで status が "success" であるか
      - 手順4c/4dのメタデータバリデーション・構造的品質検証を適用し、欠落フィールドにはデフォルト値を付与する
   c. 欠落がある場合: フェーズ2のリトライフローに従い再実行する。上限到達時は欠落を report.md に記録して次フェーズへ進む

### フィードバックループ（品質不足時の再分解）

全Wave完了・最終検証後、partial/failure のタスクが全体の50%以上の場合、decomposerを再起動して失敗タスクのみ再分解する（plan_retry.md として生成）。再分解→再実行は**1回限り**。2回目も50%以上失敗なら、そのまま集約フェーズに進み report.md に記録する。

### フェーズ3: 集約（Aggregate）

1. 集約役サブエージェントを起動する:
   - テンプレートパス（TEMPLATE_PATH）: `templates/aggregator.md`
   - 入力パス（RESULTS_DIR）: `work/cmd_xxx/results/`
   - 計画パス（PLAN_PATH）: `work/cmd_xxx/plan.md`
   - 出力パス（REPORT_PATH）: `work/cmd_xxx/report.md`
   - 要約出力パス（REPORT_SUMMARY_PATH）: `work/cmd_xxx/report_summary.md`
   - prompt に TEMPLATE_PATH + 上記パスを明記する（テンプレートの内容は含めない）
2. 結果: `work/cmd_xxx/report.md`（詳細版）と `work/cmd_xxx/report_summary.md`（要約版、≤50行）に最終報告が書かれる
3. 親は `work/cmd_xxx/report_summary.md` を読み、人間に報告する（詳細版 report.md は原則読まない。例外: 下記ステップ4のMemory MCP候補確認時のみ該当セクションを読む）
4. report_summary.md の「## Memory MCP Candidates」で候補数を確認する:
   - 候補数 > 0 の場合: report.md の「## Memory MCP追加候補（統合）」セクションのみを読み、一覧を人間に提示し、各候補の追加可否を確認する
   - 承認された候補は、サブエージェント（haiku, max_turns=5）に委譲して `mcp__memory__create_entities` で追加する（name→エンティティ名, type→entityType, observation→observations）
   - 追加結果を `execution_log.yaml` に記録する
   - 候補数が0の場合: スキップ
   - ※ 運用が安定したら人間確認を省略し自動追加に移行可能

### フェーズ4: 回顧（Retrospect）

Phase 3 完了後、cmd の結果を振り返り、失敗からは改善提案を、成功からはスキル化提案を生成する。
`config.yaml` の `retrospect.enabled` が `false` の場合、Phase 4 を完全スキップする。

#### モード判定

1. `config.yaml` の `retrospect.enabled` を確認する。`false` なら Phase 4 を完全スキップし、人間への報告に進む
2. `work/cmd_xxx/report_summary.md` の先頭20行を Read で読み、YAMLフロントマターを取得する
3. 以下のいずれかに該当すれば **fullモード**（失敗分析＋成功分析）で起動する:
   - `status` が `failure` または `partial`
   - `quality` が `RED`
   - `quality` が `YELLOW` かつ `completeness` < 80
   - `failed_tasks` が1件以上
4. 上記に該当しなければ **lightモード**（成功パターン分析のみ）で起動する

**手動トリガー**: 人間が「このcmdを振り返れ」等と明示的に指示した場合、モード判定に関係なく **fullモード** で強制起動する。

#### retrospector サブエージェントの起動

1. テンプレートパス（TEMPLATE_PATH）: `templates/retrospector.md`
2. 以下のパスとモードを prompt に明記する（テンプレートの内容は含めない）:
   - `WORK_DIR`: `work/cmd_xxx/`
   - `REPORT_PATH`: `work/cmd_xxx/report.md`
   - `RETROSPECTIVE_PATH`: `work/cmd_xxx/retrospective.md`
   - `MODE`: `full` または `light`（モード判定の結果）
3. サブエージェントを起動する（model: `config.yaml` の `retrospect.model`）
4. 結果: `work/cmd_xxx/retrospective.md` に改善提案書が書かれる

#### retrospective.md のメタデータ確認

retrospector 完了後、親セッションは `work/cmd_xxx/retrospective.md` の先頭20行を Read でメタデータを確認する:

- `improvements_accepted` > 0 の場合: 改善提案セクションを人間に提示する
- `skills_accepted` > 0 の場合: スキル化提案セクションを人間に提示する
- 両方 0 の場合: 「構造的な改善点・スキル化候補は見つかりませんでした」と報告する

#### 承認された提案の適用

**改善提案の場合:**
1. 人間に改善提案の内容を提示し、適用可否を確認する
2. 承認された提案は、人間と共に対象ファイル（テンプレート、config.yaml 等）を修正する
3. 適用結果を `execution_log.yaml` に記録する

**スキル化提案の場合:**
1. 人間にスキル化提案の内容を提示し、スキル化可否を確認する
2. 承認された提案は、スキル設計書を作成する
3. 作成結果を `execution_log.yaml` に記録する

**Memory MCP候補の場合:**
retrospective.md の「## Memory MCP追加候補」に候補がある場合:
1. 候補一覧を人間に提示し、各候補の追加可否を確認する
2. 承認された候補は、サブエージェント（haiku, max_turns=5）に委譲して `mcp__memory__create_entities` で追加する
3. 追加結果を `execution_log.yaml` に記録する

## 親セッションの行動ルール

### 基本原則
- 人間からタスクを受けたら、まず `work/cmd_xxx/` ディレクトリを作成する
- cmd番号は連番管理。既存の最大番号 + 1 を使う（並列セッション時はmkdirアトミックリトライで衝突回避）
- **「パス受け渡し係」原則に従う**（詳細は「パス受け渡し係」原則の許容範囲を参照）
- サブエージェントの結果は「返り値」ではなく「ファイル」を正データとする
- フェーズ2完了後は必ずresultファイルの存在確認を行う（リトライはフェーズ2フローに従う）

### やってはいけないこと
- 「パス受け渡し係」原則に違反すること（ファイル経由で渡せ、コンテキストに読み込むな）
- 1つのサブエージェントに複数の独立タスクを詰め込むこと（分けて並列にせよ）

### 実行ログ

親セッションは `work/cmd_xxx/execution_log.yaml` を作成し、サブエージェントの実行記録を残す。

```yaml
cmd_id: cmd_xxx
started: "2026-02-07 10:00:00"
finished: null
status: running

tasks:
  - id: 1
    role: decomposer
    task: null
    model: sonnet
    started: "2026-02-07 10:00:00"
    finished: "2026-02-07 10:01:30"
    duration_sec: 90
    status: success
    error: null
    retries: 0
    metadata_issues: []
  - id: 2
    role: worker_coder
    task: task_1
    model: sonnet
    started: "2026-02-07 10:02:00"
    finished: "2026-02-07 10:05:00"
    duration_sec: 180
    status: success
    error: null
    retries: 0
    metadata_issues: []
  - id: 3
    role: worker_researcher
    task: task_2
    model: haiku
    started: "2026-02-07 10:02:00"
    finished: null
    duration_sec: null
    status: running
    error: null
    retries: 0
    metadata_issues: []
  - id: 4
    role: aggregator
    task: null
    model: sonnet
    started: "2026-02-07 10:06:00"
    finished: "2026-02-07 10:08:00"
    duration_sec: 120
    status: success
    error: null
    retries: 0
    metadata_issues: []
  - id: 5
    role: retrospector
    task: null
    model: sonnet
    started: "2026-02-07 10:08:30"
    finished: "2026-02-07 10:10:00"
    duration_sec: 90
    status: success
    error: null
    retries: 0
    metadata_issues: []
```

**記録タイミング**:
- サブエージェント起動時: `tasks` リストにエントリを追加し、`started` に現在時刻（`date '+%Y-%m-%d %H:%M:%S'`）を記録、`status` を `running` に設定
- サブエージェント完了時: `finished` に現在時刻を記録、`duration_sec` を計算（秒数）、`status` を `success`/`failure` に更新
- リトライ時: 同じエントリの `status` を `retrying` に更新し、`started` を新しい時刻に書き換え、`retries` をインクリメント
- メタデータバリデーション時: フェーズ2手順4c/4dで必須項目の欠落や構造的品質問題を検出した場合、`metadata_issues` リストに記録する（例: `["quality missing, defaulted to YELLOW", "Sources section missing"]`）
- 全タスク完了時: トップレベルの `finished` に現在時刻を、`status` を `success`/`partial`/`failure` に更新

**Status の定義**:
- `pending`: タスクは定義されているが、まだ実行されていない（依存関係待ち）
- `running`: タスクが現在実行中
- `retrying`: タスクが失敗し、リトライ中
- `success`: タスクが正常に完了し、result ファイルが生成された
- `partial`: タスクが部分的に完了した（タイムアウト後のリトライ上限到達時など）
- `failure`: タスクが失敗し、リトライ上限に達した
- `timeout`: サブエージェントがターン上限（`config.yaml: worker_max_turns`）に到達した

**タイムスタンプフォーマット**:
- `YYYY-MM-DD HH:MM:SS`（ローカルタイム使用）
- 未記録の場合は `null` を使用

### エラーハンドリング

サブエージェントが result ファイルを生成できなかった場合:
1. execution_log.yaml の該当タスクに `status: failure` と `error` に理由を記録する
2. フェーズ2のリトライフローに従う

### チェックポイント再開（中断復帰）

親セッションが中断後に再起動した場合、未完了のcmdを途中から再開できる:

1. `work/cmd_xxx/execution_log.yaml` を読み、各タスクの `status` を確認する
2. `status` が `success` のタスクはスキップする（対応するresultファイルの存在も確認）
3. 最初の未完了（`running`/`pending`/`failure`/`timeout`/`retrying`）タスクを含むWaveから実行を再開する
4. `running` だったタスクは result ファイルが存在すればスキップ、なければ再実行する
5. execution_log.yaml が存在しない場合は最初から実行する（通常フロー）

### フェーズ省略の判断基準

タスク規模に応じて、フェーズ1（分解）とフェーズ3（集約）の省略可否を判断する。

| サブタスク数 | 依存関係 | Phase 1（分解） | Phase 3（集約） |
|:----------:|:-------:|:--------------:|:--------------:|
| 1つ | なし | 省略可 | 省略可 |
| 2つ | なし | 任意 | 任意 |
| 3つ以上 | なし | 必須 | 必須 |
| 任意 | あり | 必須 | 必須 |

- **省略可**: 親が直接 task_N.md を作成し、フェーズ2に入ってよい
- **任意**: 親の判断で省略可。ただし分解の質に自信がない場合はdecomposerを使う
- **必須**: decomposer/aggregator を必ず起動する

省略時の手順:
1. `work/cmd_xxx/request.md` に依頼を書く
2. 直接フェーズ2（実行）に入り、実働サブエージェントで処理する
3. サブタスクが1つの場合、report.md は実働の result をそのまま人間に報告してよい
4. **Phase 3 省略時の report_summary.md 生成**: Phase 4（回顧）が有効な場合、親は result_N.md のメタデータヘッダー（先頭20行）から最小限の `report_summary.md` を生成する。フォーマット:
   ```markdown
   ---
   generated_by: "claude-crew v{version}"
   date: "YYYY-MM-DD"
   cmd_id: "cmd_NNN"
   status: {result の status}
   quality: {result の quality}
   completeness: {result の completeness}
   task_count: 1
   failed_tasks: []
   ---
   # Summary: cmd_NNN
   (Phase 3 skipped — single task)
   ```

## サブエージェント起動の標準パターン

### 共通設定
- **subagent_type**: 全サブエージェント共通で `"general-purpose"` を使用
- **model**: タスクの複雑度に応じて選択（デフォルト: `config.yaml: default_model`）:
  - `"haiku"`: 軽い作業（ファイル検索、単純な変換、フォーマット整形）
  - `"sonnet"`: 標準的な作業（コード実装、分析、レビュー）
  - `"opus"`: 複雑な判断（設計、アーキテクチャ決定、難度の高い実装）

### タイムアウト制御
- Task tool の `max_turns` パラメータで各サブエージェントのターン数を制限する
- デフォルト値: `config.yaml: worker_max_turns`（未指定時: 30ターン）
- タイムアウト到達時: execution_log.yaml に Status `timeout` として記録し、リトライ対象とする
- **注意**: Task tool に秒数ベースの timeout パラメータはない。ターン数（API往復回数）で制御する

### prompt の構成
```
## Instructions
TEMPLATE_PATH: templates/xxx.md
↑ このファイルを最初に Read し、指示に従え。

## タスク固有情報
- 入力ファイル: work/cmd_xxx/tasks/task_N.md を読め
- 出力ファイル: work/cmd_xxx/results/result_N.md に書け
- [追加の指示があればここに]
```

### 並列実行のルール
- 独立したタスクは**必ず1メッセージ内で複数の Task tool 呼び出し**を行う
- 同一ファイルへの並列書き込みは禁止（ファイルパスが重複しないよう設計する）
- `config.yaml: background_threshold` 並列以上、または長時間タスクの場合は `run_in_background: true` を使用

### バックグラウンド実行
- `run_in_background: true` で起動すると、結果は output_file に書かれる
- TaskOutput tool で結果を取得する（`block: false` で状態確認可能）

## テンプレート参照規約

| 役割 | テンプレート | 用途 |
|------|-------------|------|
| 分解役 | `templates/decomposer.md` | タスクを独立サブタスクに分解 |
| 実働（デフォルト） | `templates/worker_default.md` | 汎用作業 |
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

### パーミッション制御
- `.claude/settings.json` の deny/allow リストでコマンド実行を制御する
- サブエージェントは親セッションのパーミッション設定を継承する
- deny リストの操作は自動拒否される（バイパス不可）

### 操作別ポリシー
| 操作カテゴリ | ポリシー |
|-------------|---------|
| 読み取り（git status/diff/log/branch, ls, pwd, Read, Glob, Grep） | 自動許可（allow リスト） |
| Bash ユーティリティ（date, wc, tail, grep, mkdir, bash scripts/*） | 自動許可（allow リスト） |
| Git 書き込み（git add, git commit） | 自動許可（allow リスト） |
| ファイル書き込み（Edit, Write） | 初回確認、以降セッション中許可 |
| 外部通信（git push） | 毎回確認 |
| 外部通信（curl POST/PUT/DELETE/PATCH） | 自動拒否（deny リスト） |
| 危険操作（force push, rm -rf, DROP TABLE 等） | 自動拒否（deny リスト。詳細は `.claude/settings.json` 参照） |

## Memory MCP活用

サブエージェントはタスク開始時に `mcp__memory__search_nodes` で関連知識を検索し、過去の知見を作業に活用する。

- **タイミング**: タスクファイル読了後、作業開始前に1回検索する
- **検索キーワード**: タスクの技術領域（例: `"python async"`）、プロジェクト名（例: `"project:shogun"`）、タスク種別（例: `"entityType:best_practice"`）
- **メモリが空でも正常動作する**。メモリは補助情報であり、見つからなければそのまま作業を進めてよい
- メモリの**検索**はサブエージェント側で行う。メモリへの**書き込み**は、Phase 3/4 で人間が承認した候補に限り、親セッションがサブエージェントに委譲して実行する

## コンテキスト管理

- **1依頼1サイクルがコンパクションなしで完走できること**が目標
- コンテキスト節約は「パス受け渡し係」原則の許容範囲に従う
- 長い結果を返すサブエージェントは `run_in_background: true` で起動する

### 「パス受け渡し係」原則の許容範囲

親セッションが取得してよい情報と取得してはいけない情報の境界を明確にする。

**親が取得してよい情報（メタデータ）:**
- タスク数（plan.md のテーブル行数）
- ファイルパス（RESULT_PATH、成果物パス）
- 依存関係グラフ（Depends On 列）
- タスク種別（Persona 列: researcher, writer, coder, reviewer）
- model推奨（Model 列: haiku, sonnet, opus）
- **report_summary.md の全内容**（≤50行の要約。親が人間への報告に使用する）
- **report.md の「## Memory MCP追加候補（統合）」セクション**（Memory MCP候補がある場合のみ。候補確認の例外的な読み取り）
- **resultファイルのメタデータヘッダー**（YAMLフロントマター形式、先頭20行以内）:
  - Status (success/partial/failure)
  - Quality Level (GREEN/YELLOW/RED)
  - Completeness (0-100%)
  - Errors / Warnings
  - Output files

**親が取得してはいけない情報（コンテンツ）:**
- タスクの詳細内容・本文（Description, Details 等）
- 実装方針・設計判断
- 中間結果の本文
- resultファイルの本文（メタデータヘッダー以降は読まない）

### ディレクトリ構造
```
work/
└── cmd_xxx/
    ├── request.md          … 人間の依頼内容
    ├── plan.md             … 分解役の出力（タスク分解結果）
    ├── tasks/
    │   ├── task_1.md       … サブタスク定義
    │   ├── task_2.md
    │   └── task_N.md
    ├── results/
    │   ├── result_1.md     … 各実働の成果
    │   ├── result_2.md
    │   └── result_N.md
    ├── plan_retry.md         … 再分解結果（フィードバックループ時のみ生成）
    ├── execution_log.yaml    … 実行ログ（親セッションが更新）
    ├── report.md             … 集約役の出力（最終報告・詳細版）
    ├── report_summary.md     … 集約役の出力（要約版・≤50行・親が読む）
    └── retrospective.md      … 回顧役の出力（改善提案書・Phase 4で生成）
```
