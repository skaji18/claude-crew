# Parent Session Guide — Detailed Processing Flow

このドキュメントは親セッションの詳細な処理フローを定義する。
概要は `CLAUDE.md` を参照。

## 処理フロー

人間からタスクを受けたら、以下の4フェーズで処理する。

### コミット準備

フレームワークファイルへの変更を追跡するため、cmd開始時にベースコミットを記録する:

1. 現在のHEADをベースコミットとして取得する:
   ```bash
   git rev-parse HEAD
   ```
2. execution_log.yaml のトップレベルに `base_commit: {hash}` を記録する

### フェーズ1: 分解（Decompose）

**Phase instructions**: If `config.yaml: phase_instructions.decompose` is non-empty, append its content to the decomposer prompt.

1. `work/cmd_xxx/` ディレクトリを作成する（xxxは連番）:
   ```bash
   ./scripts/new_cmd.sh
   ```
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

### Phase 1.5: Plan Validation (Optional, W1)

If `config.yaml: plan_validation` is `true`, validate the plan before execution:

#### Step 1: Launch Plan Reviewer

Use Task tool to launch a validation sub-agent:
- **Persona**: worker_reviewer
- **Model**: haiku (fast validation, max_turns: 10)
- **Prompt**:
  ```
  TEMPLATE_PATH: templates/worker_reviewer.md

  Review the execution plan against the original request.

  INPUT_FILES:
  - REQUEST_PATH: {request.md path}
  - PLAN_PATH: {plan.md path}

  OUTPUT: {work_dir}/plan_review.md

  Your review MUST end with one of:
  - APPROVE: Plan accurately implements the request
  - APPROVE-WITH-NOTES: Plan is acceptable but has minor issues (list them)
  - REJECT: Plan has critical flaws (explain specifically)

  Focus on:
  - Does the plan address all requirements in the request?
  - Are task dependencies logical?
  - Are output paths unambiguous?
  - Is the scope reasonable (check for scope_warning in plan.md)?
  ```

#### Step 2: Read Review Result

Read `plan_review.md` and check the final verdict line.

#### Step 3: Decision Logic

- **APPROVE** or **APPROVE-WITH-NOTES**: Proceed to Phase 2
  - If APPROVE-WITH-NOTES, include notes in execution log metadata

- **REJECT**: Re-run decomposer with feedback (one retry max)
  1. Append reviewer feedback to request.md (in-memory, not file modification)
  2. Re-run Phase 1 with augmented request
  3. Read new plan.md
  4. Proceed to Phase 2 regardless of second result (no infinite loop)

#### Step 4: Logging

Record in execution_log.yaml:
```yaml
plan_validation:
  enabled: true
  verdict: "APPROVE" | "APPROVE-WITH-NOTES" | "REJECT"
  retry_occurred: false | true
  notes: "reviewer notes if any"
```

**Important**: If plan_validation is false in config, skip Phase 1.5 entirely and proceed directly to Phase 2.

### フェーズ2: 実行（Execute）

**Phase instructions**: If `config.yaml: phase_instructions.execute` is non-empty, append its content to all worker prompts.

1. `work/cmd_xxx/plan.md` のタスク一覧を確認する（親はファイルパスだけ確認）
   - 確認する情報: タスク数、各タスクのファイルパス、Depends On列（依存関係）、Persona、Model
   - **タスクの詳細内容（Description等）は読まない**（パス受け渡し係原則）
2. **依存関係グラフに基づきタスクをグループ化する**:
   a. `Depends On` が `-`（依存なし）のタスクを **Wave 1** としてグループ化
   b. Wave 1 のタスクに依存するタスクを **Wave 2** としてグループ化
   c. 以降、依存元が全て処理済みのタスクを次の Wave にグループ化（全タスク割当まで繰り返し）
3. **Wave を並列実行する**:
   - **進捗メッセージ**: Wave 実行開始時にユーザーに通知する（ETA付き）
     - 例: `Wave 1/3: 3 tasks running (~2 min est.)`
     - ETA が算出不可の場合: `Wave 1/3: 3 tasks running`
     - 背景ワーク時: `Wave 1/3: 3 tasks running (background)`
   - 各タスクに対して実働サブエージェントを起動する:
     - テンプレートパス（TEMPLATE_PATH）: `templates/worker_xxx.md` からタスクに適したものを選択
     - 入力パス: `work/cmd_xxx/tasks/task_N.md`
     - 出力パス: `work/cmd_xxx/results/result_N.md`
     - prompt に TEMPLATE_PATH + 入出力パスを含める（テンプレートの内容は含めない）
   - **独立したタスクは1メッセージ内で複数の Task tool 呼び出しを行い並列実行する**

   #### Wave進捗メッセージの ETA 計算

   Wave の推定所要時間を算出する方法:

   1. **stats.sh データが利用可能な場合**（10+ 実行ログ）:
      - `bash scripts/stats.sh` を実行し、ペルソナ別の平均実行時間を抽出
      - 現在の Wave に属する各タスクについて、そのペルソナの平均時間を合計
      - 合計を `config.yaml: max_parallel` で除算し、Wave の推定所要時間を算出

   2. **データ不足の場合**（<10 ログ）:
      - フォールバック推定値を使用:
        - researcher: 60秒
        - writer: 90秒
        - coder: 120秒
        - reviewer: 45秒
      - 各タスクのペルソナで推定値を合計
      - 合計を `max_parallel` で除算

   3. **人間が読みやすい形式に丸める**:
      - < 90秒: "~1 min"
      - 90-150秒: "~2 min"
      - > 150秒: "~N min" (最も近い分に四捨五入)

   **エッジケース**:
   - ETA が算出不可（stats データなし、フォールバック不可）: ETA 句を省略、Wave メッセージのみ
   - 全タスクが background ワークの場合: ETA は省略し、代わりに "(background)" を表示

4. **Wave 完了確認 → 次の Wave へ進む**:
   a. 現在の Wave の全タスクが完了したら、`results/` 内の result_N.md 存在をチェック
   b. 各resultファイルを `./scripts/validate_result.sh RESULT_PATH PERSONA` で検証する:
      - JSON結果の `status` が `"fail"` → リトライ対象
      - JSON結果の `status` が `"pass"` + `issues` あり → execution_log.yaml の `metadata_issues` に記録
      - JSON結果の `status` が `"pass"` + `issues` なし → 完了
   c. Read (limit=20) でメタデータヘッダーを読み、status/quality/completeness を確認:
      - status: "success" → 完了とみなす
      - status: "partial" または "failure" → リトライ対象
      - メタデータヘッダーがない場合 → 従来通り存在チェックのみで判定（フォールバック）
   d. **メタデータバリデーション**: 手順cで読み取ったYAMLフロントマターの必須3項目を検証する:
      - **status**: 欠落時 → `status: failure` として扱う（品質不明のため安全側に倒す）
      - **quality**: 欠落時 → `quality: YELLOW` を付与（品質不明のため）
      - **completeness**: 欠落時 → `completeness: 0` として扱う
      - 検証結果を execution_log.yaml の該当タスクの `metadata_issues` に記録する（例: `quality missing, defaulted to YELLOW`）
      - 3項目全て存在する場合は検証パス。`metadata_issues` は空リスト `[]` のまま
   e. 欠落またはstatus=failure/partialの場合は該当タスクをリトライ（最大 `config.yaml: max_retries` 回）
   f. **部分結果の転送**: リトライ上限に達したタスクがある場合:
      - 該当タスクの result を `status: failure` として記録する（result ファイルが未生成の場合、親が最小限の failure result を生成する）
      - Phase 3（集約）に進む際、aggregator の prompt に `FAILED_TASKS: [N, M]` を追記する
      - aggregator はこれらのタスクの結果が欠落していることを前提に統合を行う
   g. **カスケード障害検出**: Wave N-1 で失敗したタスクに依存する Wave N のタスクがある場合:
      - 依存元タスクが failure/partial の場合、依存先タスクを自動スキップする
      - スキップされたタスクは execution_log.yaml に `status: skipped` + `error: "dependency task_M failed"` として記録する
      - スキップされたタスクの result は生成しない（aggregator に FAILED_TASKS として通知される）
   h. 全resultがstatus=success（またはリトライ上限に達した）ら、次のWaveを並列実行
   i. **依存元が未完了のタスクは絶対に実行しない**
   j. 全 Wave が完了するまで繰り返す
   - **Wave 完了時の進捗メッセージ**: 結果サマリをユーザーに通知する
     - 例: `Wave 1/3 完了 (3/3 success)`
5. 結果: `work/cmd_xxx/results/result_N.md` に各タスクの成果が書かれる
   - **全Wave完了時の進捗メッセージ**: 全体サマリをユーザーに通知する
     - 例: `Phase 2 完了: 5/5 タスク success`
6. **タイムアウト処理**: worker が `config.yaml: worker_max_turns` に到達した場合:
   a. execution_log.yaml の該当タスクに `status: timeout` として記録する
   b. 該当タスクをリトライ対象とする（最大 `config.yaml: max_retries` 回）
   c. リトライ上限到達時: result を `status: partial` として記録し、次の Wave へ進む
7. **最終検証**: 全Waveの完了後、以下を実行する:
   a. `work/cmd_xxx/results/` ディレクトリ内のファイル一覧を取得（Glob tool使用）
   b. plan.md のタスク一覧と照合し、以下を確認:
      - 欠落している result_N.md がないか
      - 各resultを `./scripts/validate_result.sh RESULT_PATH PERSONA` で検証し、メタデータヘッダーで status が "success" であるか
      - 手順4d のメタデータバリデーションを適用し、欠落フィールドにはデフォルト値を付与する
   c. 欠落がある場合: フェーズ2のリトライフローに従い再実行する。上限到達時は欠落を report.md に記録して次フェーズへ進む
8. **失敗サマリ出力**: Phase 2 完了時に failure/partial タスクが存在する場合、以下の構造化メッセージをユーザーに出力する:
   ```
   ⚠️ Phase 2 completed with failures:
   - Task N ({persona}): {status} — {error summary}
   - Task M ({persona}): {status} — {error summary}
   Action: {次のアクション — 再分解/集約続行/手動介入}
   ```
   - failure タスクがある場合でも Phase 3 に進む（aggregator が部分結果を統合する）
   - 50%以上が failure の場合のみフィードバックループを起動する
9. **実行時間チェック**: `config.yaml: max_cmd_duration_sec` が設定されている場合:
   - cmd 開始時刻（execution_log.yaml の `started`）からの経過時間を計算する
   - 閾値を超えた場合、ユーザーに警告を出力する: `⚠️ cmd_NNN has exceeded max duration (${elapsed}s > ${max}s)`
   - 警告のみ。実行を中断しない

### フィードバックループ（品質不足時の再分解）

全Wave完了・最終検証後、partial/failure のタスクが全体の50%以上の場合、decomposerを再起動して失敗タスクのみ再分解する（plan_retry.md として生成）。再分解→再実行は**1回限り**。2回目も50%以上失敗なら、そのまま集約フェーズに進み report.md に記録する。

### フェーズ3: 集約（Aggregate）

**Phase instructions**: If `config.yaml: phase_instructions.aggregate` is non-empty, append its content to the aggregator prompt.

1. 集約役サブエージェントを起動する:
   - テンプレートパス（TEMPLATE_PATH）: `templates/aggregator.md`
   - 入力パス（RESULTS_DIR）: `work/cmd_xxx/results/`
   - 計画パス（PLAN_PATH）: `work/cmd_xxx/plan.md`
   - 出力パス（REPORT_PATH）: `work/cmd_xxx/report.md`
   - 要約出力パス（REPORT_SUMMARY_PATH）: `work/cmd_xxx/report_summary.md`
   - prompt に TEMPLATE_PATH + 上記パスを明記する（テンプレートの内容は含めない）
2. 結果: `work/cmd_xxx/report.md`（詳細版）と `work/cmd_xxx/report_summary.md`（要約版、≤50行）に最終報告が書かれる
3. 親は `work/cmd_xxx/report_summary.md` を読み、人間に報告する（詳細版 report.md は原則読まない）
4. Memory MCP 候補は report.md に記録されたまま保持する（Phase 4 完了後に一括提示）

### フェーズ4: 回顧（Retrospect）

**Phase instructions**: If `config.yaml: phase_instructions.retrospect` is non-empty, append its content to the retrospector prompt.

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

- `improvements_accepted` > 0 の場合: 改善提案あり
- `skills_accepted` > 0 の場合: スキル化提案あり
- 両方 0 の場合: 「構造的な改善点・スキル化候補は見つかりませんでした」と報告する

### Phase 4 完了後: 一括承認フロー

Phase 4 完了後（または Phase 4 スキップ時は Phase 3 完了後）、以下の候補を**一括で**ユーザーに提示する:

1. **改善提案一覧**: retrospective.md の改善提案セクション（Phase 4 の出力）
2. **スキル提案一覧**: retrospective.md のスキル化提案セクション（Phase 4 の出力）
3. **Memory MCP 候補一覧**: report.md + retrospective.md の Memory MCP 候補を統合
   - report.md の「## Memory MCP追加候補（統合）」セクションのみを読む
   - retrospective.md の「## Memory MCP追加候補」セクションを読む
   - 重複を除去して一覧化

ユーザーが一括で承認/却下を判断する。承認された候補のみ処理する:

#### Rejection Memory Storage

When user rejects retrospector proposals:

1. Identify the rejection category:
   - Template modification proposals → `workflow:rejected_proposal:template_modification`
   - Skill proposals → `workflow:rejected_proposal:skill`
   - Improvement proposals → `workflow:rejected_proposal:improvement`

2. Store Memory MCP entity:
   ```
   mcp__memory__create_entities({
     entities: [{
       name: "workflow:rejected_proposal:{category}",
       entityType: "rejection_memory",
       observations: [
         "Rejected on {date} in {cmd_id}",
         "Proposal type: {description}",
         "Reason: {user's stated reason if any}"
       ]
     }]
   })
   ```

3. This prevents retrospector from repeatedly proposing the same category in future cmds.

**Note**: Rejection memory storage is optional. Only store if the user explicitly rejects a category of proposals (not individual proposals).

- **改善提案**: 承認された各改善に対して以下を実行:
  1. 対象ファイルに変更を適用する
  2. CHANGELOG.md の `## [Unreleased]` に適切なカテゴリ（Added/Changed/Fixed/Deprecated/Removed）でエントリを追加する
     - フォーマット: `- **{対象}** ({改善ID}) — {説明}`
  3. 変更ファイルと CHANGELOG.md をステージする:
     ```bash
     git add {変更ファイル} CHANGELOG.md
     ```
  4. Conventional Commits 形式でコミットする:
     ```bash
     git commit -m "$(cat <<'EOF'
     {type}({scope}): {description}

     Co-Authored-By: Claude <noreply@anthropic.com>
     EOF
     )"
     ```
  5. **コミットしない場合**: work/ 配下のみの変更、またはユーザーが却下した場合

  **type マッピング**:

  | 改善の種類 | type |
  |-----------|------|
  | 新機能追加 | `feat` |
  | 既存機能の変更・強化 | `feat` |
  | バグ修正 | `fix` |
  | リファクタリング | `refactor` |
  | ドキュメントのみ | `docs` |

  **scope**: 変更対象ディレクトリ（`templates`, `config`, `scripts`, `docs` 等）

- **スキル化提案**: スキル設計書を作成
- **Memory MCP候補**: サブエージェント（haiku, max_turns=5）に委譲して `mcp__memory__create_entities` で追加

全ての適用結果を `execution_log.yaml` に記録する。

### コミット履歴の確認

一括承認フロー完了後、cmd中に作成されたコミットをユーザーに表示する:

```bash
git log --oneline ${BASE_COMMIT}..HEAD
```

コミットがない場合（承認された改善が work/ 外のファイルを変更しなかった場合）は表示をスキップする。

## Phase Instructions Injection (F23)

`config.yaml: phase_instructions` に非空の文字列が含まれている場合、対応するフェーズプロンプトに追記する:

### Injection Points

- **Phase 1 (Decompose)**: `phase_instructions.decompose` を decomposer プロンプトの TEMPLATE_PATH 指示の後に追記
- **Phase 2 (Execute)**: `phase_instructions.execute` を全 worker プロンプトの TEMPLATE_PATH 指示の後に追記
- **Phase 3 (Aggregate)**: `phase_instructions.aggregate` を aggregator プロンプトの TEMPLATE_PATH 指示の後に追記
- **Phase 4 (Retrospect)**: `phase_instructions.retrospect` を retrospector プロンプトの TEMPLATE_PATH 指示の後に追記

### Format

追加フェーズ指示は以下の形式で挿入する:

```
## Instructions
TEMPLATE_PATH: templates/decomposer.md
↑ このファイルを最初に Read し、指示に従え。

このフェーズの追加指示:
{phase_instructions.decompose}

## タスク固有情報
...
```

### Use Cases

- プロジェクト固有の制約（例: "vendor/ ディレクトリ内のファイルは絶対に変更しない"）
- ワークフロー設定（例: "機能実装時は必ずテストファイルも含める"）
- ドメイン別ガイドライン（例: "docs/standards.md の社内コーディング規約に従う"）
- セキュリティ要件（例: "API キーが含まれるファイルは絶対に修正しない"）

### 重要な注意

- Phase instructions は**追記される**（テンプレート指示に優先されない）
- テンプレートの指示がフェーズ指示より優先される
- 空文字列の場合、追記は行われない

## 親セッションの行動ルール

### 基本原則
- 人間からタスクを受けたら、まず `work/cmd_xxx/` ディレクトリを作成する
- cmd番号は連番管理。既存の最大番号 + 1 を使う（並列セッション時はmkdirアトミックリトライで衝突回避）
- **「パス受け渡し係」原則に従う**（詳細は下記「パス受け渡し係」原則の許容範囲を参照）
- サブエージェントの結果は「返り値」ではなく「ファイル」を正データとする
- フェーズ2完了後は必ずresultファイルの存在確認を行う（リトライはフェーズ2フローに従う）

### コンテキスト衛生

- **Wave完了メッセージ**: pass/fail のステータスとタスク数のみ報告する。validate_result.sh の JSON 出力全文をコンテキストに蓄積しない
  - Good: `Wave 1/3 完了 (3/3 success)`
  - Bad: `Wave 1 results: {"complete_marker": true, "line_count": 245, ...}`
- **result ファイル読み取り制限**: メタデータヘッダー（先頭20行）のみ読む。本文は絶対に読まない
- **execution_log.yaml 更新**: 各エントリは最小限のフィールドのみ。エラーメッセージは1行以内に要約する
- **進捗メッセージ**: 定型フォーマットを使い、自由文を避ける

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
base_commit: "cfa49a0"

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
- メタデータバリデーション時: フェーズ2手順4dで必須項目の欠落や構造的品質問題を検出した場合、`metadata_issues` リストに記録する（例: `["quality missing, defaulted to YELLOW", "Sources section missing"]`）
- 全タスク完了時: トップレベルの `finished` に現在時刻を、`status` を `success`/`partial`/`failure` に更新

**Status の定義**:
- `pending`: タスクは定義されているが、まだ実行されていない（依存関係待ち）
- `running`: タスクが現在実行中
- `retrying`: タスクが失敗し、リトライ中
- `success`: タスクが正常に完了し、result ファイルが生成された
- `partial`: タスクが部分的に完了した（タイムアウト後のリトライ上限到達時など）
- `failure`: タスクが失敗し、リトライ上限に達した
- `timeout`: サブエージェントがターン上限（`config.yaml: worker_max_turns`）に到達した
- `skipped`: タスクの依存元が失敗したため、実行をスキップした

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
| 1つ | なし | 必須 | 省略可 |
| 2つ | なし | 必須 | 任意 |
| 3つ以上 | なし | 必須 | 必須 |
| 任意 | あり | 必須 | 必須 |

- **必須**: decomposer/aggregator を必ず起動する
- **省略可**: aggregator を省略し、親が直接 report を生成してよい（Phase 1 は省略不可）
- **任意**: 親の判断で aggregator を省略可。ただし複数結果の統合が必要な場合は aggregator を使う

**Phase 1 例外条件**: 以下の場合に限り Phase 1 を省略してよい
- 1ファイル1箇所の typo修正（誤字脱字のみ）
- 既存ファイルへの1行追加・削除（新規実装・ロジック変更を含まない）
- `config.yaml` の単一値変更（version bump、閾値変更等）
- `execution_log.yaml` の更新
- 承認フローの実施（Memory MCP書き込み、改善提案のコミット等）
- ユーザーへの報告・説明のみ

上記例外を除き、**Phase 1 は必須**である。タスクが単純に見えても、decomposer を起動してタスク分解を行うこと。

Phase 1 省略時の手順（例外条件に該当する場合のみ）:
1. `work/cmd_xxx/request.md` に依頼を書く
2. 親が直接 `work/cmd_xxx/tasks/task_1.md` を作成する
3. フェーズ2（実行）に入り、実働サブエージェントで処理する
4. サブタスクが1つの場合、report.md は実働の result をそのまま人間に報告してよい
5. **Phase 3 省略時の report_summary.md 生成**: Phase 4（回顧）が有効な場合、親は result_N.md のメタデータヘッダー（先頭20行）から最小限の `report_summary.md` を生成する。フォーマット:
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

## 「パス受け渡し係」原則の許容範囲

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

## Memory MCP活用

サブエージェントはタスク開始時に `mcp__memory__search_nodes` で関連知識を検索し、過去の知見を作業に活用する。

- **タイミング**: タスクファイル読了後、作業開始前に1回検索する
- **検索キーワード**: タスクの技術領域（例: `"python async"`）、プロジェクト名（例: `"project:shogun"`）、タスク種別（例: `"entityType:best_practice"`）
- **メモリが空でも正常動作する**。メモリは補助情報であり、見つからなければそのまま作業を進めてよい
- メモリの**検索**はサブエージェント側で行う。メモリへの**書き込み**は、一括承認フローで人間が承認した候補に限り、親セッションがサブエージェントに委譲して実行する

## 操作別ポリシー

### Permission System Overview

claude-crew uses a 3-layer permission control system to balance safety with usability:

**1. Settings Layer (Static Rules)**
- File: `.claude/settings.json`
- Purpose: Blanket allow/ask/deny patterns (fast, no computation)
- Examples: `Bash(ls*)` auto-approved, `Bash(rm -rf *)` auto-rejected

**2. Hook Layer (Dynamic Analysis)**
- File: `.claude/hooks/permission-fallback` (Python 3)
- Purpose: Context-aware validation with 8 validation phases
- Examples: Script containment checks, path verification, subcommand analysis

**3. Subcommand Configuration (Danger Pattern Blocking)**
- File: `.claude/hooks/permission-config.json`
- Purpose: Prevent dangerous subcommands even if parent command is in allow list
- Examples: `git:push`, `gh:pr:merge` → routed to dialog regardless of `git *`/`gh *` allow pattern

**Flow Summary**: deny patterns → allow patterns → hook validation (8 phases) → ask patterns → user dialog

#### 3-Layer Control Table

| Layer | File | Scope | Example |
|-------|------|-------|---------|
| **Static** | `.claude/settings.json` | Glob-based patterns | `allow: ["Bash(ls*)"]`, `deny: ["Bash(rm -rf *)"]` |
| **Dynamic** | `.claude/hooks/permission-fallback` | Syntax/path/containment checks | Phase 1-7 validation pipeline |
| **Subcommand** | `.claude/hooks/permission-config.json` | Dangerous subcommand blocking | `"git:push"`, `"gh:pr:merge"` |

### Phase 7B2: Subcommand Rejection (NEW in v1.0-rc)

**Problem**: Before cmd_053, patterns like `Bash(git *)` in allow list auto-approved dangerous operations:
- `git push` (forced pushes to main)
- `git reset --hard` (destructive changes)
- `git clean -f` (data loss)
- Similar issues with `gh *` pattern

**Solution** (cmd_053): Remove git/gh from allow list → route through hook → Phase 7B2 matches subcommand patterns in `permission-config.json`.

**How It Works**:
1. User invokes: `git push origin main`
2. Settings.json: `git *` NOT in allow list (removed in cmd_053)
3. Hook invoked: 8-phase validation
4. Phase 7B2: Extract subcommand `push` → check `"git:push"` in `subcommand_ask` → REJECT (show dialog)
5. Result: Dialog shown instead of auto-approval

**Dangerous Patterns Blocked** (from `permission-config.json: subcommand_ask`):
- `git:push` — Any git push operation
- `git:clean` — Discard tracked files
- `git:reset:--hard` — Force discard changes
- `git:checkout:.` — Discard all working changes
- `git:restore:.` — Restore all files (newer git)
- `gh:pr:merge` — Merge pull request
- `gh:repo:delete` — Delete repository
- `gh:repo:archive` — Archive repository
- `gh:release:delete` — Delete release

**Safe Commands Still Auto-Approved**:
- `git status`, `git log`, `git diff` (no subcommand match)
- `gh pr view`, `gh issue list` (no subcommand match)

### PermissionRequest Hook Implementation

**File**: `.claude/hooks/permission-fallback` (Python 3 executable)

**Purpose**: Auto-approve project-local script execution and safe general commands while rejecting dangerous operations.

**8 Validation Phases**:

| Phase | Name | Purpose | Action if Failed |
|-------|------|---------|------------------|
| S0 | Null byte rejection | Guard against null byte injection | REJECT |
| 1 | Control character & tool_name validation | Ensure valid JSON and tool identifier | REJECT |
| 1.5 | Safe suffix stripping | Remove harmless output redirects (2>&1, \|\| true) | CONTINUE |
| 2 | Shell syntax rejection | Block pipes, redirects, variable expansion, command substitution | REJECT |
| 3 | Command parsing | Split interpreter/script/args | CONTINUE |
| 4 | Flag normalization | Classify safe vs dangerous flags | CONTINUE |
| 5 | Path normalization | Lexical canonicalization without filesystem traversal | CONTINUE |
| 6 | scripts/ and .claude/hooks/ containment | Auto-approve if script in project namespace | ALLOW ✅ |
| 7 | General command approval | Route to sub-phases 7A-7D | See below |

**Phase 7 (General Command) Sub-phases**:
- **7A**: Extract command name (e.g., `curl`, `git`, `node`)
- **7B**: Check ALWAYS_ASK list (`curl`, `sudo`, `npm`, etc.) → REJECT ❌
- **7B2 (NEW)**: Check `permission-config.json: subcommand_ask` patterns → REJECT ❌
  - Example: `git push` matches `"git:push"` → show dialog
  - Example: `git status` does NOT match → continue to 7C
- **7C**: Collect path-like arguments
- **7D**: Verify all paths contained in project → ALLOW ✅

**Configuration Files**:
- `.claude/hooks/permission-config.json` — Interpreter flags, ALWAYS_ASK list, subcommand_ask patterns
- `.claude/settings.json` — allow/ask/deny patterns, hook command path

**Testing**: `.claude/hooks/test-permission-fallback.sh` (190+ regression tests)

**Rollback**: Original bash version preserved as `.claude/hooks/permission-fallback.sh.bak`

### パーミッション判定フロー

Bash tool 呼び出し時の優先度順の判定フロー:

```
Bash tool 呼び出し
    ↓
[Tier 1] settings.json deny → 自動拒否
    ↓ not matched
[Tier 2] settings.json allow → 自動許可
    ↓ not matched
[Tier 3] PermissionRequest hook
    ├── Phases S0-2: シェル構文ガード → 拒否
    │    └─ 失敗 → REJECT ❌
    │
    ├── Phases 3-6: scripts/ or .claude/hooks/ 含義判定
    │    └─ プロジェクト内スクリプト → ALLOW ✅
    │
    └── Phase 7: 汎用コマンド承認
        ├── 7A: コマンド名抽出
        ├── 7B: ALWAYS_ASK リスト一致 → REJECT ❌
        │    (curl, sudo, npm, node 等)
        ├── 7B2: サブコマンド拒否パターン → REJECT ❌
        │    (git push, gh pr merge 等)
        ├── 7C: パス引数収集
        └── 7D: パス引数がプロジェクト内 → ALLOW ✅
    │
    ↓ not matched
[Tier 4] settings.json ask → 条件付き確認
    ↓ not matched
ユーザーに確認ダイアログ表示
```

deny > allow > hook > ask > default の優先順位で判定される。hookは allow に該当しないコマンドでも、条件を満たせば自動承認できる補完メカニズムである。Phase 7B2（サブコマンド拒否）により、危険な操作は確認ダイアログにルーティングされる。

### 操作カテゴリ別ポリシー

3段階制御: deny（自動拒否）> ask（毎回確認）> allow（自動許可）

| 操作カテゴリ | ポリシー |
|-------------|---------|
| Bash 基本ユーティリティ（ls, grep） | 自動許可（allow リスト） |
| Git 破壊操作（push, reset --hard, clean -f, checkout ., restore .） | 毎回確認（hook Phase 7B2 経由で subcommand_ask 拒否） |
| GitHub CLI 危険操作（pr merge, repo delete, repo archive） | 毎回確認（hook Phase 7B2 経由で subcommand_ask 拒否） |
| Git 安全操作（status, log, diff, add, commit） | 自動許可（hook Phase 7D 経由） |
| GitHub CLI 安全操作（pr view, issue list） | 自動許可（hook Phase 7D 経由） |
| スクリプト実行（scripts/ 配下・.claude/hooks/ 配下） | hook Phase 6 経由で自動許可（詳細は `.claude/hooks/permission-fallback` 参照） |
| 汎用コマンド（プロジェクト内パス）（find, cat, wc, stat, tree 等） | hook Phase 7 経由で自動許可（パス封じ込め確認） |
| ALWAYS_ASK（ネットワーク・権限昇格・インタプリタ） | 毎回確認（curl, sudo, npm, node 等。詳細は `permission-config.json: always_ask` 参照） |
| ファイル操作ツール（Read, Glob, Grep） | 自動許可（allow リスト） |
| ファイル書き込み（Edit, Write） | 自動許可（allow リスト） |
| HTTP DELETE（curl -X DELETE） | 自動拒否（deny リスト） |
| 危険操作（rm -rf, rm -r, pipe to sh/bash, chmod 777, DROP TABLE 等） | 自動拒否（deny リスト。詳細は `.claude/settings.json` 参照） |

## Memory MCP候補の品質基準

Memory MCPに記録する知見は以下の基準を満たすこと:

**即却下（以下に該当する候補は生成・承認しない）**:
- 特定cmd参照（`cmd_NNN`）を含む候補
- claude-crew内部アーキテクチャの記述（decomposer, aggregator, parent session, Phase, execution_log等）
- Claudeの事前学習で既知の一般知識（プロジェクト固有文脈がないOWASP/NIST/CVE等）
- 環境設定の重複（CLAUDE.md / config.yaml に既存の情報）
- 未昇華の事実記録（教訓・判断基準への変換が必要）
- 行動に落とせない抽象論

**必須条件（全て満たすこと）**:
- Cross-cmd適用可能性: 3つ以上の将来cmdで異なるドメインに適用可能
- 行動変容可能性: 読んだサブエージェントが具体的に行動を変えられる
- 観測の具体性: 条件と効果が定量的または具体的

**命名規約**: `{domain}:{category}:{identifier}`
- Good: `security:env_file_exposure_risk`, `user:shogun:preference:report_brevity`
- Bad: `claude-crew:failure_pattern:result_file_missing` (内部アーキテクチャ)

**Note**: The "Bad" example above is an intentional illustration of the instant-reject filter. Do not use `claude-crew:*` naming in actual Memory MCP entities — it violates the domain-general principle.

**1cmdあたりの候補上限**: `config.yaml: retrospect.memory.max_candidates_per_cmd`（デフォルト: 5件）

## Claude Skills提案の品質基準

Skills提案は以下の5条件を全て満たす場合のみ提案する:

1. `/skill-name [args]` でユーザーが直接起動できる自己完結型ワークフローである
2. claude-crew以外の3つ以上のプロジェクトで使える
3. 月3回以上呼び出される想定がある
4. 3ステップ以上の定型手順がある
5. 生成元システム（claude-crew）外部に価値を提供する

上記を満たさない成功パターンは、テンプレート改善（IMP-NNN）またはMemory MCP候補として提案する。

**3軸スコアリング閾値**: `config.yaml: retrospect.memory.skill_min_score`（デフォルト: 12点/15点満点）

## ディレクトリ構造
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
